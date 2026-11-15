// Show / hide password buttons (ClaperWeb.Component.PasswordReveal, Jose
// 2026-11-15). One listener for every password field in the app.
//
// On live pages the button's LiveView JS commands are run, so the change
// survives LiveView's redraws (a shown password stays shown while typing).
// On regular pages there is nothing to redraw, so the input is changed
// directly. Sending a form hides its passwords again, so the browser offers
// to save them.

function inLiveView(el) {
  return el.closest("[data-phx-session]") !== null;
}

function set(liveSocket, button, show) {
  const input = document.getElementById(button.getAttribute("aria-controls"));
  if (!input) return;

  if (liveSocket && inLiveView(button)) {
    liveSocket.execJS(
      button,
      show ? button.dataset.showJs : button.dataset.hideJs,
    );
  } else {
    const label = show ? button.dataset.labelHide : button.dataset.labelShow;
    input.type = show ? "text" : "password";
    button.setAttribute("aria-pressed", String(show));
    button.setAttribute("aria-label", label);
    button.setAttribute("data-tooltip", label);
  }
}

export function installPasswordReveal(liveSocket) {
  document.addEventListener("click", (e) => {
    const button = e.target.closest("[data-password-reveal]");
    if (!button) return;

    const input = document.getElementById(button.getAttribute("aria-controls"));
    if (!input) return;

    set(liveSocket, button, input.type === "password");
    input.focus({ preventScroll: true });
  });

  // Before a form is sent: passwords hidden again
  document.addEventListener(
    "submit",
    (e) => {
      const form = e.target;
      if (!(form instanceof HTMLFormElement)) return;
      form
        .querySelectorAll('[data-password-reveal][aria-pressed="true"]')
        .forEach((button) => set(liveSocket, button, false));
    },
    true,
  );
}
