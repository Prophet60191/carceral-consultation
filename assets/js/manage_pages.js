// The manage screen's swipeable cards on phones and tablets (Jose,
// 2026-11-16; assets/css/manage_pages.css). This hook draws the dots at the
// bottom, marks the card in view, and keeps you on that card: opening,
// saving or closing an interaction changes the page's address, and the row
// would otherwise go back to its first card (Jose: "I should not be kicked
// from this card unless I scroll"). The swiping itself is the browser's
// scroll snapping. The dots live in #manage-dots, which the page never
// redraws, so LiveView's updates can't undo them.

export const ManagePages = {
  mounted() {
    this.dots = document.getElementById("manage-dots");
    this.onScroll = () => {
      if (this.frame) return;
      this.frame = requestAnimationFrame(() => {
        this.frame = null;
        if (!this.restoring) this.remember(this.index());
        this.mark();
      });
    };
    this.el.addEventListener("scroll", this.onScroll, { passive: true });
    window.addEventListener("resize", this.onScroll);
    this.restore();
    this.draw();
  },

  // Cards may come or go (a presentation added), so the dots follow; and
  // the card you were on stays in view
  updated() {
    this.restore();
    this.draw();
  },

  destroyed() {
    this.el.removeEventListener("scroll", this.onScroll);
    window.removeEventListener("resize", this.onScroll);
    if (this.frame) cancelAnimationFrame(this.frame);
  },

  pages() {
    return this.el.querySelectorAll(".manage-page");
  },

  index() {
    return Math.round(this.el.scrollLeft / (this.el.clientWidth || 1));
  },

  // The card in view, per event, for this tab (and across the page's own
  // address changes); a plain variable when the browser keeps no storage
  key() {
    return `cc-manage-card:${location.pathname.replace(/\/manage.*$/, "")}`;
  },

  remember(index) {
    this.saved = index;
    try {
      sessionStorage.setItem(this.key(), String(index));
    } catch (_) {}
  },

  recalled() {
    if (this.saved != null) return this.saved;
    try {
      const value = parseInt(sessionStorage.getItem(this.key()), 10);
      return Number.isNaN(value) ? 0 : value;
    } catch (_) {
      return 0;
    }
  },

  restore() {
    // Only where the cards scroll sideways (phones and tablets)
    if (this.el.scrollWidth <= this.el.clientWidth) return;
    const want = Math.min(this.recalled(), this.pages().length - 1);
    if (want < 0 || this.index() === want) return;
    this.restoring = true;
    this.el.scrollTo({ left: want * this.el.clientWidth, behavior: "instant" });
    requestAnimationFrame(() => {
      this.restoring = false;
      this.mark();
    });
  },

  draw() {
    if (!this.dots) return;
    const count = this.pages().length;
    if (this.dots.children.length !== count) {
      this.dots.replaceChildren(
        ...Array.from({ length: count }, () => document.createElement("span")),
      );
    }
    this.mark();
  },

  mark() {
    const index = this.index();
    Array.from(this.dots?.children || []).forEach((dot, i) => {
      dot.toggleAttribute("data-active", i === index);
    });
  },
};
