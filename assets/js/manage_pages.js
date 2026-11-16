// The manage screen's swipeable cards on phones and tablets (Jose,
// 2026-11-16; assets/css/manage_pages.css). This hook only draws the dots
// at the bottom and marks the card in view; the swiping itself is the
// browser's scroll snapping. The dots live in #manage-dots, which the page
// never redraws, so LiveView's updates can't undo them.

export const ManagePages = {
  mounted() {
    this.dots = document.getElementById("manage-dots");
    this.onScroll = () => {
      if (this.frame) return;
      this.frame = requestAnimationFrame(() => {
        this.frame = null;
        this.mark();
      });
    };
    this.el.addEventListener("scroll", this.onScroll, { passive: true });
    window.addEventListener("resize", this.onScroll);
    this.draw();
  },

  // Cards may come or go (a presentation added), so the dots follow
  updated() {
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
    const width = this.el.clientWidth || 1;
    const index = Math.round(this.el.scrollLeft / width);
    Array.from(this.dots?.children || []).forEach((dot, i) => {
      dot.toggleAttribute("data-active", i === index);
    });
  },
};
