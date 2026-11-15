// The app's confirmation dialog (ClaperWeb.AlertDialog), replacing the
// browser's confirm() for every element with data-confirm (Jose, 2026-11-14).
//
// A click listener on window, in the capture phase and installed before
// phoenix_html and LiveView see any click, stops a click on a data-confirm
// element and opens the dialog instead. Continue replays the click with
// data-confirm removed for that moment, so the link, form button or
// phx-click runs exactly as before; Cancel or Esc drops it.
//
// Optional attributes: data-confirm-title, data-confirm-action and
// data-confirm-variant="destructive" (red confirm button and a trash can,
// or a warning sign with data-confirm-icon="warning").

export function installAlertDialog() {
  let trigger = null;

  const parts = () => {
    const dialog = document.getElementById("cc-alert-dialog");
    if (!dialog || typeof dialog.showModal !== "function") return null;
    return {
      dialog,
      title: dialog.querySelector("#cc-alert-title"),
      description: dialog.querySelector("#cc-alert-description"),
      media: dialog.querySelector("[data-alert-media]"),
      cancel: dialog.querySelector("[data-alert-cancel]"),
      action: dialog.querySelector("[data-alert-action]"),
    };
  };

  const close = (confirmed) => {
    const p = parts();
    const el = trigger;
    trigger = null;
    if (p && p.dialog.open) p.dialog.close();
    if (!el) return;
    if (confirmed && el.isConnected) {
      const message = el.getAttribute("data-confirm");
      el.removeAttribute("data-confirm");
      try {
        el.click();
      } finally {
        if (el.isConnected) el.setAttribute("data-confirm", message);
      }
    } else if (el.isConnected && typeof el.focus === "function") {
      el.focus();
    }
  };

  const open = (el) => {
    const p = parts();
    if (!p) return false;
    const destructive = el.getAttribute("data-confirm-variant") === "destructive";
    trigger = el;
    p.title.textContent = el.getAttribute("data-confirm-title") || p.dialog.dataset.defaultTitle;
    p.description.textContent = el.getAttribute("data-confirm") || "";
    p.description.hidden = !p.description.textContent;
    p.action.textContent =
      el.getAttribute("data-confirm-action") || p.dialog.dataset.defaultAction;
    p.action.classList.toggle("btn-primary", !destructive);
    p.action.classList.toggle("btn-error", destructive);
    p.media.hidden = !destructive;
    // A trash can (the default) or data-confirm-icon="warning" for actions
    // that can't be taken back but delete nothing (block, end, stop, revoke).
    const icon = el.getAttribute("data-confirm-icon") === "warning" ? "warning" : "delete";
    p.media.querySelectorAll("[data-alert-icon]").forEach((svg) => {
      svg.style.display = svg.dataset.alertIcon === icon ? "" : "none";
    });
    p.dialog.dataset.variant = destructive ? "destructive" : "default";
    p.dialog.showModal();
    p.cancel.focus();
    return true;
  };

  window.addEventListener(
    "click",
    (e) => {
      const el = e.target instanceof Element ? e.target.closest("[data-confirm]") : null;
      if (!el || el.closest("#cc-alert-dialog")) return;
      if (!open(el)) return; // no dialog on this page: the browser's confirm() still guards it
      e.preventDefault();
      e.stopImmediatePropagation();
    },
    true,
  );

  document.addEventListener("click", (e) => {
    if (!(e.target instanceof Element)) return;
    if (e.target.closest("[data-alert-cancel]")) close(false);
    else if (e.target.closest("[data-alert-action]")) close(true);
  });

  // Esc closes a <dialog> with a "cancel" event: treat it as Cancel.
  document.addEventListener(
    "cancel",
    (e) => {
      if (e.target && e.target.id === "cc-alert-dialog") {
        e.preventDefault();
        close(false);
      }
    },
    true,
  );
}
