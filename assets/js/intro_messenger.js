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

    // Phones: swipe the sheet down (from its handle or header) to close it
    const panel = this.el.querySelector("#intro-messenger-panel");
    this.onTouchStart = (e) => {
      if (!e.target.closest(".intro-messenger-grab, .intro-messenger-head"))
        return;
      if (e.target.closest("button")) return;
      this.swipeFrom = e.touches[0].clientY;
    };
    this.onTouchMove = (e) => {
      if (this.swipeFrom == null) return;
      const dy = Math.max(0, e.touches[0].clientY - this.swipeFrom);
      panel.style.transform = `translateY(${dy}px)`;
      panel.style.transition = "none";
    };
    this.onTouchEnd = (e) => {
      if (this.swipeFrom == null) return;
      const dy = e.changedTouches[0].clientY - this.swipeFrom;
      this.swipeFrom = null;
      panel.style.transform = "";
      panel.style.transition = "";
      if (dy > 80) this.pushEvent("close-messenger", {});
    };
    panel?.addEventListener("touchstart", this.onTouchStart, { passive: true });
    panel?.addEventListener("touchmove", this.onTouchMove, { passive: true });
    panel?.addEventListener("touchend", this.onTouchEnd);

    // Phones: while the keyboard is open, the sheet sits on top of it
    // (--cc-kb: how much of the window the keyboard covers)
    this.onViewport = () => {
      const vv = window.visualViewport;
      if (!vv) return;
      const covered = Math.max(
        0,
        window.innerHeight - vv.height - vv.offsetTop,
      );
      this.el.style.setProperty("--cc-kb", `${Math.round(covered)}px`);
    };
    window.visualViewport?.addEventListener("resize", this.onViewport);
    window.visualViewport?.addEventListener("scroll", this.onViewport);
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
    window.visualViewport?.removeEventListener("resize", this.onViewport);
    window.visualViewport?.removeEventListener("scroll", this.onViewport);
  },

  isOpen() {
    return this.el.dataset.open === "true";
  },
};
