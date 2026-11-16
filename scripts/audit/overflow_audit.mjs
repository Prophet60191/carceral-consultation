// The overflow audit (Jose, 2026-11-16; scripts/audit/README.md): visits
// every page at phone, tablet and computer sizes and reports anything that
// doesn't fit:
//
//   wider-page   the page is wider than the screen, so it shifts sideways
//                under your thumb (and the elements that cause it)
//   sticks-out   an element reaches past the edge of the box it sits in
//   cut-off      an element is chopped off by a box that hides overflow
//                (text shortened with "…" on purpose is not reported)
//   text-spills  text (a long word, a link) runs past its own box
//
// Things that are meant to scroll sideways (the manage screen's card row,
// tab strips) are left alone, as are pop-ups placed on the screen, and
// anything marked data-overflow-ok="why" (a deliberate nudge).
//
//   cd scripts/audit && npm install
//   AUDIT_BASE=http://localhost:4000 AUDIT_EMAIL=… AUDIT_PASSWORD_FILE=… \
//   AUDIT_VARS='{"code":"abcde",…}' node overflow_audit.mjs [pages.json]
//
// Browsers: WebKit (Safari's engine, for iPhone and iPad profiles) and
// Chrome; set AUDIT_CHROME to Chrome's path if it isn't the macOS default.

import { webkit, chromium, devices } from "playwright-core";
import { readFileSync, writeFileSync } from "node:fs";

const BASE = process.env.AUDIT_BASE || "http://localhost:4000";
const VARS = JSON.parse(process.env.AUDIT_VARS || "{}");
const PAGES = JSON.parse(
  readFileSync(
    process.argv[2] || new URL("./pages.json", import.meta.url),
    "utf8",
  ),
);
const CHROME =
  process.env.AUDIT_CHROME ||
  "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome";
const ONLY = (process.env.AUDIT_ONLY || "").split(",").filter(Boolean);

const DEVICES = [
  ["iPhone SE", "webkit", devices["iPhone SE"]],
  ["iPhone", "webkit", devices["iPhone 13"]],
  ["iPad", "webkit", devices["iPad (gen 7)"]],
  ["iPad sideways", "webkit", devices["iPad (gen 7) landscape"]],
  ["Laptop", "chromium", { viewport: { width: 1440, height: 900 } }],
];

const fill = (path) =>
  path.replace(/\{(\w+)\}/g, (_, key) => VARS[key] ?? `{${key}}`);

// Runs in the page: every element that doesn't fit, outermost first
function findOverflow() {
  const vw = document.documentElement.clientWidth;
  const problems = [];
  const style = (el) => getComputedStyle(el);
  const visible = (el) => {
    const s = style(el);
    if (
      s.display === "none" ||
      s.visibility === "hidden" ||
      Number(s.opacity) === 0
    )
      return false;
    const r = el.getBoundingClientRect();
    return r.width > 1 && r.height > 1;
  };
  const label = (el) => {
    let out = el.tagName.toLowerCase();
    if (el.id) out += `#${el.id}`;
    const classes = [...el.classList]
      .filter((c) => !c.includes(":") && !c.includes("["))
      .slice(0, 3);
    if (classes.length) out += "." + classes.join(".");
    const parent =
      el.closest("[id]:not(:scope)") || el.parentElement?.closest("[id]");
    if (parent && parent !== el && parent.id) out = `#${parent.id} … ${out}`;
    return out;
  };
  const text = (el) =>
    (el.innerText || el.value || el.getAttribute("aria-label") || "")
      .trim()
      .replace(/\s+/g, " ")
      .slice(0, 50);
  // Boxes that scroll sideways on purpose (card rows, tab strips)
  const scrollsX = (el) => /(auto|scroll)/.test(style(el).overflowX);
  const insideScroller = (el) => {
    for (
      let a = el.parentElement;
      a && a !== document.body;
      a = a.parentElement
    )
      if (scrollsX(a)) return true;
    return false;
  };
  const placed = (el) => {
    for (let a = el; a && a !== document.body; a = a.parentElement) {
      const p = style(a).position;
      if (p === "fixed") return true;
    }
    return false;
  };
  const allowed = (el) => el.closest("[data-overflow-ok]") !== null;
  const tiny = (el) => {
    const r = el.getBoundingClientRect();
    return r.width <= 2 && r.height <= 2; // screen-reader-only text
  };
  const reported = new Set();
  const outerReported = (el) => {
    for (let a = el.parentElement; a; a = a.parentElement)
      if (reported.has(a)) return true;
    return false;
  };

  // 1. The page wider than the screen
  const pageWidth = document.documentElement.scrollWidth;
  if (pageWidth > vw + 1) {
    problems.push({
      kind: "wider-page",
      by: pageWidth - vw,
      element: "html",
      text: "",
    });
    for (const el of document.body.querySelectorAll("*")) {
      if (
        !(el instanceof HTMLElement) ||
        !visible(el) ||
        tiny(el) ||
        allowed(el) ||
        insideScroller(el)
      )
        continue;
      if (placed(el) && style(el).position !== "fixed") continue;
      const r = el.getBoundingClientRect();
      if (r.right > vw + 1 && !outerReported(el)) {
        reported.add(el);
        problems.push({
          kind: "wider-page",
          by: Math.round(r.right - vw),
          element: label(el),
          text: text(el),
        });
      }
    }
  }

  // 2 and 3. Sticking out of, or cut off by, the box around it
  for (const el of document.body.querySelectorAll("*")) {
    if (!(el instanceof HTMLElement) || !visible(el) || tiny(el) || allowed(el))
      continue;
    const s = style(el);
    if (s.position === "absolute" || s.position === "fixed" || placed(el))
      continue;
    let parent = el.parentElement;
    while (parent && style(parent).display === "contents")
      parent = parent.parentElement;
    if (!parent || parent === document.documentElement) continue;
    if (scrollsX(parent) || insideScroller(el)) continue;
    const r = el.getBoundingClientRect();
    const p = parent.getBoundingClientRect();
    const ps = style(parent);
    const left = p.left + parseFloat(ps.borderLeftWidth);
    const right = p.right - parseFloat(ps.borderRightWidth);
    const over = Math.max(r.right - right, left - r.left);
    if (over <= 1.5 || outerReported(el)) continue;
    const clipped = ps.overflowX !== "visible";
    if (
      clipped &&
      (s.textOverflow === "ellipsis" ||
        style(parent).textOverflow === "ellipsis")
    )
      continue;
    reported.add(el);
    problems.push({
      kind: clipped ? "cut-off" : "sticks-out",
      by: Math.round(over),
      element: label(el),
      inside: label(parent),
      text: text(el),
    });
  }

  // 4. Text running past its own box (a long word or link)
  for (const el of document.body.querySelectorAll("*")) {
    if (
      !(el instanceof HTMLElement) ||
      !visible(el) ||
      tiny(el) ||
      allowed(el) ||
      placed(el) ||
      insideScroller(el)
    )
      continue;
    const s = style(el);
    if (s.overflowX !== "visible" || s.display.startsWith("inline")) continue;
    if (
      ![...el.childNodes].some((n) => n.nodeType === 3 && n.textContent.trim())
    )
      continue;
    if (el.scrollWidth > el.clientWidth + 1 && !outerReported(el)) {
      reported.add(el);
      problems.push({
        kind: "text-spills",
        by: el.scrollWidth - el.clientWidth,
        element: label(el),
        text: text(el),
      });
    }
  }
  return problems;
}

async function signIn(page) {
  const password = readFileSync(process.env.AUDIT_PASSWORD_FILE, "utf8").trim();
  await page.goto(`${BASE}/users/log_in`);
  await page.fill('input[name="user[email]"]', process.env.AUDIT_EMAIL);
  await page.fill('input[name="user[password]"]', password);
  await Promise.all([
    page.waitForNavigation(),
    page.press('input[name="user[password]"]', "Enter"),
  ]);
}

// Extra steps a page needs before checking it
const STEPS = {
  // The manage screen on phones: each card of the row in turn, then the
  // settings window
  async manageCards(page, check) {
    const count = await page.evaluate(
      () => document.querySelectorAll("#manage-pages .manage-page").length,
    );
    for (let i = 0; i < count; i++) {
      await page.evaluate(
        (i) =>
          document
            .getElementById("manage-pages")
            ?.scrollTo({
              left: document.getElementById("manage-pages").clientWidth * i,
            }),
        i,
      );
      await page.waitForTimeout(300);
      await check(`card ${i + 1}`);
    }
    const settings = page
      .locator("button[phx-click='toggle-settings-modal']:visible")
      .first();
    if (await settings.count()) {
      await settings.click({ timeout: 3000 });
      await page.waitForTimeout(500);
      await check("settings window");
      await page
        .locator("#settings-modal button[phx-click='toggle-settings-modal']")
        .first()
        .click({ timeout: 3000 });
      await page.waitForTimeout(300);
    }
  },
  async openAddMenu(page, check) {
    const trigger = page.locator("[data-combobox-trigger]:visible").first();
    if (await trigger.count()) {
      await trigger.click({ timeout: 3000 });
      await page.waitForTimeout(300);
      await check("Add menu open");
      await page.keyboard.press("Escape");
    }
  },
  async openMessenger(page, check) {
    const toggle = page.locator("[data-messenger-toggle]:visible").first();
    if (await toggle.count()) {
      await toggle.click({ timeout: 3000 });
      await page.waitForTimeout(500);
      await check("messenger open");
    }
  },
};

const results = [];
for (const [deviceName, engine, options] of DEVICES) {
  if (ONLY.length && !ONLY.includes(deviceName)) continue;
  const browser =
    engine === "webkit"
      ? await webkit.launch()
      : await chromium.launch({ executablePath: CHROME });
  const staff = await (await browser.newContext(options)).newPage();
  await signIn(staff);
  const guest = await (await browser.newContext(options)).newPage();

  for (const entry of PAGES) {
    if (entry.devices && !entry.devices.includes(deviceName)) continue;
    const page = entry.signedIn ? staff : guest;
    const url = fill(entry.path);
    try {
      await page.goto(BASE + url, { waitUntil: "networkidle", timeout: 20000 });
    } catch (_) {
      await page.goto(BASE + url).catch(() => {});
    }
    await page.waitForTimeout(800);
    const check = async (state) => {
      const problems = await page.evaluate(findOverflow);
      for (const p of problems)
        results.push({
          device: deviceName,
          page: entry.name,
          url,
          state,
          ...p,
        });
    };
    await check("as it opens");
    for (const step of entry.steps || []) {
      try {
        await STEPS[step](page, check);
      } catch (error) {
        results.push({
          device: deviceName,
          page: entry.name,
          url,
          state: step,
          kind: "step-failed",
          by: 0,
          element: "",
          text: String(error.message).split("\n")[0],
        });
      }
    }
  }
  await browser.close();
}

writeFileSync(
  process.env.AUDIT_OUT || "overflow_report.json",
  JSON.stringify(results, null, 2),
);
const byKey = new Map();
for (const r of results) {
  const key = `${r.page} | ${r.kind} | ${r.element}`;
  const seen = byKey.get(key) || {
    ...r,
    devices: new Set(),
    states: new Set(),
  };
  seen.devices.add(r.device);
  seen.states.add(r.state);
  seen.by = Math.max(seen.by, r.by);
  byKey.set(key, seen);
}
console.log(`${results.length} findings, ${byKey.size} distinct`);
for (const r of byKey.values()) {
  console.log(
    `- [${r.kind}] ${r.page} (${[...r.states].join(", ")}): ${r.element}` +
      (r.inside ? ` in ${r.inside}` : "") +
      ` by ${r.by}px on ${[...r.devices].join(", ")}` +
      (r.text ? ` — "${r.text}"` : ""),
  );
}
