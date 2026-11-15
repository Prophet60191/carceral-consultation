// Tooltips (2026-11-15): shadcn/ui's Tooltip, base-nova style, without
// React. Any element with data-tooltip="text" gets one, on mouse hover and
// on keyboard focus. Options on the same element:
//   data-tooltip-side="top|bottom|left|right"  (default top; flips to fit)
//   data-tooltip-shortcut="Q"                  (a key shown beside the text)
// One shared bubble (#cc-tooltip) in the browser's top layer, so no panel
// clips it. Escape, scrolling, clicking or the page changing closes it.
// Styles: assets/css/tooltip.css. Guide: docs/THEME.md, "Tooltips".

const OFFSET = 4; // px between trigger and bubble (shadcn's sideOffset)
const MARGIN = 8; // px kept from the window's edges
const OPPOSITE = { top: "bottom", bottom: "top", left: "right", right: "left" };

let bubble, textEl, kbdEl, arrowEl;
let current = null; // the trigger whose tooltip is open

function ensureBubble() {
  if (bubble && document.body.contains(bubble)) return;
  bubble = document.createElement("div");
  bubble.id = "cc-tooltip";
  bubble.className = "cc-tooltip";
  bubble.setAttribute("role", "tooltip");
  if ("popover" in bubble) bubble.setAttribute("popover", "manual");
  textEl = document.createElement("span");
  kbdEl = document.createElement("kbd");
  kbdEl.className = "cc-tooltip-kbd";
  arrowEl = document.createElement("span");
  arrowEl.className = "cc-tooltip-arrow";
  arrowEl.setAttribute("aria-hidden", "true");
  bubble.append(textEl, kbdEl, arrowEl);
  document.body.appendChild(bubble);
}

function place(trigger, wanted) {
  const r = trigger.getBoundingClientRect();
  const b = bubble.getBoundingClientRect();
  const vw = window.innerWidth;
  const vh = window.innerHeight;

  const fits = {
    top: r.top - b.height - OFFSET >= MARGIN,
    bottom: r.bottom + b.height + OFFSET <= vh - MARGIN,
    left: r.left - b.width - OFFSET >= MARGIN,
    right: r.right + b.width + OFFSET <= vw - MARGIN,
  };
  const side =
    fits[wanted] || !fits[OPPOSITE[wanted]] ? wanted : OPPOSITE[wanted];

  let x, y;
  if (side === "top" || side === "bottom") {
    x = r.left + r.width / 2 - b.width / 2;
    y = side === "top" ? r.top - b.height - OFFSET : r.bottom + OFFSET;
  } else {
    y = r.top + r.height / 2 - b.height / 2;
    x = side === "left" ? r.left - b.width - OFFSET : r.right + OFFSET;
  }
  const cx = Math.min(Math.max(x, MARGIN), vw - b.width - MARGIN);
  const cy = Math.min(Math.max(y, MARGIN), vh - b.height - MARGIN);

  bubble.style.left = `${Math.round(cx)}px`;
  bubble.style.top = `${Math.round(cy)}px`;
  bubble.dataset.side = side;

  // The arrow points at the trigger's middle, even when the bubble shifted
  if (side === "top" || side === "bottom") {
    const ax = Math.min(
      Math.max(r.left + r.width / 2 - cx - 4, 6),
      b.width - 14,
    );
    arrowEl.style.left = `${ax}px`;
    arrowEl.style.top = "";
  } else {
    const ay = Math.min(
      Math.max(r.top + r.height / 2 - cy - 4, 6),
      b.height - 14,
    );
    arrowEl.style.top = `${ay}px`;
    arrowEl.style.left = "";
  }
}

function show(trigger) {
  const text = trigger.dataset.tooltip;
  if (!text) return;
  ensureBubble();
  if (current && current !== trigger) hide();

  textEl.textContent = text;
  kbdEl.textContent = trigger.dataset.tooltipShortcut || "";
  bubble.dataset.state = "open";
  bubble.dataset.visible = "false";
  if (bubble.showPopover && !bubble.matches(":popover-open"))
    bubble.showPopover();
  place(trigger, trigger.dataset.tooltipSide || "top");

  // Screen readers read the tooltip with the control
  const target = describedTarget(trigger);
  target.setAttribute("aria-describedby", "cc-tooltip");
  current = trigger;
  requestAnimationFrame(() => {
    if (current === trigger) bubble.dataset.visible = "true";
  });
}

function hide() {
  if (!bubble || !current) return;
  describedTarget(current).removeAttribute("aria-describedby");
  current = null;
  bubble.dataset.visible = "false";
  bubble.dataset.state = "closed";
  if (bubble.hidePopover && bubble.matches(":popover-open"))
    bubble.hidePopover();
}

// The control itself, or the first focusable one inside a wrapper
function describedTarget(trigger) {
  if (trigger.matches("a, button, input, select, textarea, [tabindex]"))
    return trigger;
  return (
    trigger.querySelector("a, button, input, select, textarea, [tabindex]") ||
    trigger
  );
}

export function installTooltips() {
  // Mouse only: on touch screens a tap is a click, not a hover
  document.addEventListener("pointerover", (e) => {
    if (e.pointerType === "touch") return;
    const trigger = e.target.closest("[data-tooltip]");
    if (trigger && trigger !== current) show(trigger);
  });
  document.addEventListener("pointerout", (e) => {
    if (!current) return;
    const to = e.relatedTarget;
    if (!to || !current.contains(to)) hide();
  });
  document.addEventListener("focusin", (e) => {
    const trigger = e.target.closest("[data-tooltip]");
    // Keyboard focus only (not the focus a mouse click leaves behind)
    if (trigger && e.target.matches(":focus-visible")) show(trigger);
  });
  document.addEventListener("focusout", () => hide());
  document.addEventListener("keydown", (e) => {
    if (e.key === "Escape") hide();
  });
  document.addEventListener("pointerdown", () => hide(), true);
  window.addEventListener("scroll", () => hide(), true);
  window.addEventListener("resize", () => hide());
  // LiveView: page changes, or the trigger was redrawn away
  window.addEventListener("phx:page-loading-start", () => hide());
  new MutationObserver(() => {
    if (current && !current.isConnected) hide();
  }).observe(document.documentElement, { childList: true, subtree: true });
}
