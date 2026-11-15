// The landing page's panels (ClaperWeb.Landing, Jose 2026-11-15).
//
// "Join event" and "Log in" open their panel; Back (the button, the
// browser's, or Escape) closes it. The open panel is kept on
// <html data-landing>, outside anything LiveView redraws, and in the
// address as #join / #log-in so the browser's Back button closes it.
// LiveView ignores changes after the "#", so nothing reloads.
//
// A page reached directly at /join or /users/log_in opens with that panel
// (data-landing-initial on the page, styled before this script runs).

const HASHES = { join: "#join", login: "#log-in" };

function landing() {
  return document.querySelector("[data-landing-root]");
}

// What the address says should be open
function panelFromLocation(root) {
  if (location.hash === HASHES.join) return "join";
  if (location.hash === HASHES.login) return "login";
  if (location.hash === "#none") return "none";
  return root.dataset.landingInitial || "none";
}

function show(panel, { focus = true } = {}) {
  const root = landing();
  if (!root) return;

  document.documentElement.dataset.landing = panel;

  root.querySelectorAll("[data-landing-open]").forEach((button) => {
    button.setAttribute("aria-expanded", String(button.dataset.landingOpen === panel));
  });

  if (focus && panel !== "none") {
    const field = root.querySelector(
      `[data-landing-panel="${panel}"] input:not([type=hidden])`,
    );
    // After the panel starts to appear (it's hidden until then)
    setTimeout(() => field && field.focus({ preventScroll: true }), 60);
  }
}

function open(panel) {
  if (panelFromLocation(landing()) === panel) return show(panel);
  history.pushState({ landing: panel }, "", HASHES[panel]);
  show(panel);
}

function close() {
  const root = landing();
  if (!root) return;

  // Opened from this page: going back closes it, as the browser's Back would
  if (history.state && history.state.landing) {
    history.back();
  } else {
    history.pushState({ landing: "none" }, "", "#none");
    show("none");
  }
}

export function installLanding() {
  const sync = () => {
    const root = landing();
    if (root) show(panelFromLocation(root), { focus: false });
  };

  document.addEventListener("click", (e) => {
    if (!landing() || !(e.target instanceof Element)) return;

    const opener = e.target.closest("[data-landing-open]");
    if (opener) {
      e.preventDefault();
      return open(opener.dataset.landingOpen);
    }

    if (e.target.closest("[data-landing-close]")) {
      e.preventDefault();
      close();
    }
  });

  document.addEventListener("keydown", (e) => {
    if (e.key === "Escape" && landing() && document.documentElement.dataset.landing !== "none") {
      close();
    }
  });

  window.addEventListener("hashchange", sync);
  window.addEventListener("popstate", sync);
  // Live navigation away and back: start from the new page's own state
  window.addEventListener("phx:page-loading-stop", sync);

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", sync);
  } else {
    sync();
  }
}
