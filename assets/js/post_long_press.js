// Staff messages on phones and tablets (Jose, 2026-11-16): a long press on
// a message bubble opens the same actions as hovering on a computer (reply,
// pin, block, delete). Tapping elsewhere, or using one of the actions,
// closes them.
//
// The message list is redrawn whenever a message arrives, which undoes
// classes a script adds. So the menu is opened and closed with LiveView JS
// commands (data-open-menu, data-close-menus on the row), which LiveView
// keeps through its redraws.

const PRESS_MS = 450;
const MOVE_PX = 10;

export const PostLongPress = {
  mounted() {
    this.touch = window.matchMedia("(pointer: coarse)");
    this.bubble = () => this.el.querySelector("[data-post-bubble]");

    this.onStart = (event) => {
      if (!this.touch.matches || !event.target.closest("[data-post-bubble]"))
        return;
      const point = event.touches[0];
      this.start = { x: point.clientX, y: point.clientY };
      this.timer = setTimeout(() => this.open(), PRESS_MS);
    };
    this.onMove = (event) => {
      if (!this.start) return;
      const point = event.touches[0];
      if (
        Math.abs(point.clientX - this.start.x) > MOVE_PX ||
        Math.abs(point.clientY - this.start.y) > MOVE_PX
      ) {
        this.cancel(); // a scroll or a swipe, not a press
      }
    };
    this.onEnd = () => this.cancel();
    // The browser's own long-press menu (copy, look up) would cover ours
    this.onContextMenu = (event) => {
      if (this.touch.matches && event.target.closest("[data-post-bubble]")) {
        event.preventDefault();
      }
    };

    this.el.addEventListener("touchstart", this.onStart, { passive: true });
    this.el.addEventListener("touchmove", this.onMove, { passive: true });
    this.el.addEventListener("touchend", this.onEnd);
    this.el.addEventListener("touchcancel", this.onEnd);
    this.el.addEventListener("contextmenu", this.onContextMenu);
  },

  destroyed() {
    this.cancel();
    document.removeEventListener("pointerdown", this.onOutside, true);
  },

  cancel() {
    clearTimeout(this.timer);
    this.start = null;
  },

  open() {
    this.start = null;
    const { liveSocket } = window;
    liveSocket.execJS(this.el, this.el.dataset.closeMenus);
    liveSocket.execJS(this.el, this.el.dataset.openMenu);
    navigator.vibrate?.(10);

    // Closes on the next tap anywhere: outside, or on one of the actions
    // (after it has done its job)
    this.onOutside = (event) => {
      if (event.target.closest(".post-actions")) {
        setTimeout(() => this.close(), 300);
      } else {
        this.close();
      }
      document.removeEventListener("pointerdown", this.onOutside, true);
    };
    setTimeout(
      () => document.addEventListener("pointerdown", this.onOutside, true),
      0,
    );
  },

  close() {
    window.liveSocket.execJS(this.el, this.el.dataset.closeMenus);
  },
};
