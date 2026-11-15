// The intro page's messenger (Jose, 2026-11-15; ClaperWeb.EventLive.Show).
// The page decides open or closed (data-open, from the server); this hook
// closes it on a click outside it or Escape, and, when it opens, shows the
// newest messages and puts the cursor in the message box.

function inDialogOrTooltip(target) {
  // Confirmations, the name prompt and tooltips sit outside the messenger
  // but belong to it: clicking them must not close it.
  return target.closest("dialog, #cc-alert-dialog, #cc-tooltip") !== null;
}

export const IntroMessenger = {
  mounted() {
    this.wasOpen = this.isOpen();

    this.onPointerDown = (e) => {
      if (!this.isOpen()) return;
      if (this.el.contains(e.target) || inDialogOrTooltip(e.target)) return;
      this.pushEvent("close-messenger", {});
    };

    this.onKeyDown = (e) => {
      if (e.key !== "Escape" || !this.isOpen()) return;
      if (document.querySelector("dialog[open]")) return;
      this.pushEvent("close-messenger", {});
      this.el.querySelector("#intro-messenger-toggle")?.focus();
    };

    document.addEventListener("pointerdown", this.onPointerDown, true);
    document.addEventListener("keydown", this.onKeyDown);
  },

  updated() {
    const open = this.isOpen();
    if (open && !this.wasOpen) {
      const feed = this.el.querySelector("#chat-feed");
      if (feed) feed.scrollTop = feed.scrollHeight;
      const box = this.el.querySelector("#postFormTA:not([disabled])");
      if (box) setTimeout(() => box.focus({ preventScroll: true }), 60);
    }
    this.wasOpen = open;
  },

  destroyed() {
    document.removeEventListener("pointerdown", this.onPointerDown, true);
    document.removeEventListener("keydown", this.onKeyDown);
  },

  isOpen() {
    return this.el.dataset.open === "true";
  },
};
