// The messenger (Jose, 2026-11-15; ClaperWeb.EventLive.Messenger): one
// component for the intro page and the live room. Its panel and bubble are
// found by [data-messenger-panel] and [data-messenger-toggle].
// The page decides open or closed (data-open, from the server); this hook
// closes it on a click outside it or Escape, and, when it opens, shows the
// newest messages (and, on computers, puts the cursor in the message box).
// Nothing here sets styles on the messenger itself: LiveView redraws it every
// second (the countdown) and would undo them (2026-11-15, Jose's iPhone).

function inDialogOrTooltip(target) {
  // Confirmations, the name prompt and tooltips sit outside the messenger
  // but belong to it: clicking them must not close it.
  return target.closest("dialog, #cc-alert-dialog, #cc-tooltip") !== null;
}

export const Messenger = {
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
      this.el.querySelector("[data-messenger-toggle]")?.focus();
    };

    document.addEventListener("pointerdown", this.onPointerDown, true);
    document.addEventListener("keydown", this.onKeyDown);

    // Phones: swipe the sheet down (from its handle or header) to close it
    const panel = this.el.querySelector("[data-messenger-panel]");
    this.onTouchStart = (e) => {
      if (!e.target.closest(".messenger-grab, .messenger-head")) return;
      if (e.target.closest("button")) return;
      this.swipeFrom = e.touches[0].clientY;
    };
    this.onTouchMove = (e) => {
      if (this.swipeFrom == null) return;
      const dy = Math.max(0, e.touches[0].clientY - this.swipeFrom);
      const root = document.documentElement;
      root.classList.add("cc-sheet-dragging");
      root.style.setProperty("--sheet-drag", `${dy}px`);
    };
    this.onTouchEnd = (e) => {
      if (this.swipeFrom == null) return;
      const dy = e.changedTouches[0].clientY - this.swipeFrom;
      this.swipeFrom = null;
      const root = document.documentElement;
      root.classList.remove("cc-sheet-dragging");
      root.style.removeProperty("--sheet-drag");
      if (dy > 80) this.pushEvent("close-messenger", {});
    };
    panel?.addEventListener("touchstart", this.onTouchStart, { passive: true });
    panel?.addEventListener("touchmove", this.onTouchMove, { passive: true });
    panel?.addEventListener("touchend", this.onTouchEnd);

    // Phones: the page behind the open sheet doesn't scroll (a class on
    // <html>, outside what LiveView redraws every second for the countdown).
    // Safari itself keeps the message box above the keyboard.
    this.touch = window.matchMedia("(pointer: coarse)");
  },

  updated() {
    const open = this.isOpen();
    if (open !== this.wasOpen) {
      document.documentElement.classList.toggle("cc-sheet-open", open);
    }
    if (open && !this.wasOpen) {
      const feed = this.el.querySelector("#chat-feed");
      if (feed) feed.scrollTop = feed.scrollHeight;
      // The cursor goes in the box on computers only: on a phone, focusing it
      // without a tap leaves it focused without a keyboard, and the next tap
      // then misbehaves (iPhone). There, the person taps the box.
      const box = this.el.querySelector("#postFormTA:not([disabled])");
      if (box && !this.touch.matches) {
        setTimeout(() => box.focus({ preventScroll: true }), 60);
      }
    }
    this.wasOpen = open;
  },

  destroyed() {
    document.documentElement.classList.remove("cc-sheet-open");
    document.removeEventListener("pointerdown", this.onPointerDown, true);
    document.removeEventListener("keydown", this.onKeyDown);
  },

  isOpen() {
    return this.el.dataset.open === "true";
  },
};
