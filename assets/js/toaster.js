// Toasts (ClaperWeb.Toast; shadcn base-nova Toast). Works on every page,
// LiveView or not: any [data-toast] that appears in the toaster is opened,
// timed, and closed here (Jose, 2026-11-14).
//
//   * opens with a short slide-up; closes after 5 s (errors 8 s, loading
//     never), the timer paused while hovered, focused or the tab is hidden
//   * × or a sideways swipe closes it at once
//   * a flash toast carries data-on-close (a LiveView JS command clearing
//     its flash), run when it closes so it doesn't come back
//   * new toasts: window.ccToast({type, title, description}) or, from a
//     LiveView, ClaperWeb.Toast.push/4 (a "toast" event)

const DURATION = { error: 8000, loading: 0 };
const DEFAULT_DURATION = 5000;
const MAX_VISIBLE = 4;
let counter = 0;

function close(el) {
  if (!el.isConnected || el.dataset.state === "closed") return;
  el.dataset.state = "closed";
  window.clearTimeout(el._toastTimer);
  const onClose = el.dataset.onClose;
  if (onClose && window.liveSocket && window.liveSocket.isConnected()) {
    window.liveSocket.execJS(el, onClose);
  }
  window.setTimeout(() => {
    if (el.dataset.client === "true") el.remove();
    else el.hidden = true;
  }, 200);
}

function startTimer(el) {
  window.clearTimeout(el._toastTimer);
  const ms = el._toastLeft;
  if (!ms) return;
  el._toastStarted = Date.now();
  el._toastTimer = window.setTimeout(() => close(el), ms);
}

function pauseTimer(el) {
  if (!el._toastTimer || !el._toastLeft) return;
  window.clearTimeout(el._toastTimer);
  el._toastTimer = null;
  el._toastLeft = Math.max(1000, el._toastLeft - (Date.now() - el._toastStarted));
}

function setup(el) {
  if (el._toastReady || el.closest("template")) return;
  el._toastReady = true;
  const type = el.dataset.type || "info";
  el._toastLeft = type in DURATION ? DURATION[type] : DEFAULT_DURATION;

  el.querySelector("[data-toast-close]")?.addEventListener("click", () => close(el));
  el.addEventListener("pointerenter", () => pauseTimer(el));
  el.addEventListener("pointerleave", () => startTimer(el));
  el.addEventListener("focusin", () => pauseTimer(el));
  el.addEventListener("focusout", () => startTimer(el));

  // Swipe sideways to close (touch or mouse drag).
  let startX = null;
  el.addEventListener("pointerdown", (e) => {
    if (e.target.closest("button, a")) return;
    startX = e.clientX;
    el.setPointerCapture?.(e.pointerId);
  });
  el.addEventListener("pointermove", (e) => {
    if (startX === null) return;
    const dx = e.clientX - startX;
    el.style.transform = `translateX(${dx}px)`;
    el.style.opacity = String(Math.max(0, 1 - Math.abs(dx) / 200));
  });
  const end = (e) => {
    if (startX === null) return;
    const dx = e.clientX - startX;
    startX = null;
    if (Math.abs(dx) > 80) {
      close(el);
    } else {
      el.style.transform = "";
      el.style.opacity = "";
    }
  };
  el.addEventListener("pointerup", end);
  el.addEventListener("pointercancel", end);

  // Too many at once: close the oldest.
  const open = [...document.querySelectorAll("#cc-toaster [data-toast]:not([data-state=closed]):not([hidden])")];
  open.slice(0, Math.max(0, open.length - MAX_VISIBLE)).forEach(close);

  window.requestAnimationFrame(() => {
    el.dataset.state = "open";
    if (!document.hidden) startTimer(el);
  });
}

export function addToast({ type = "info", title = "", description = "" } = {}) {
  const toaster = document.getElementById("cc-toaster");
  const proto = document.getElementById("cc-toast-template")?.content.querySelector("[data-toast]");
  if (!toaster || !proto) return null;
  const el = proto.cloneNode(true);
  el.id = `toast-client-${++counter}`;
  el.dataset.type = type;
  el.dataset.client = "true";
  el.removeAttribute("phx-update");
  el.setAttribute("role", type === "error" ? "alert" : "status");
  el.setAttribute("aria-live", type === "error" ? "assertive" : "polite");
  el.querySelector("[data-toast-title]").textContent = title;
  const desc = el.querySelector("[data-toast-description]");
  if (desc) {
    desc.textContent = description || "";
    desc.hidden = !description;
  }
  toaster.appendChild(el);
  setup(el);
  return el.id;
}

export function installToaster() {
  const scan = () => document.querySelectorAll("#cc-toaster [data-toast]").forEach(setup);
  scan();
  new MutationObserver(scan).observe(document.body, { childList: true, subtree: true });

  document.addEventListener("visibilitychange", () => {
    document.querySelectorAll("#cc-toaster [data-toast][data-state=open]").forEach((el) =>
      document.hidden ? pauseTimer(el) : startTimer(el),
    );
  });

  window.ccToast = addToast;
  window.addEventListener("phx:toast", (e) => addToast(e.detail || {}));
}
