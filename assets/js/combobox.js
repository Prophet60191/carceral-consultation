// The "Add" combobox (ClaperWeb.Component.Combobox; Jose, 2026-11-16): a
// button opening a panel with a search box and the choices. Typing filters
// them; ↑ ↓ move, Enter picks, Escape closes; a tap outside closes it.
//
// The button and panel sit in a block the page never redraws, so the open
// panel, its position and the search survive LiveView's redraws. The panel
// is placed on the screen (position: fixed) so a scrolling card never cuts
// it off.

const normalize = (text) =>
  (text || "").toLowerCase().normalize("NFD").replace(/[̀-ͯ]/g, "");

export const Combobox = {
  mounted() {
    this.touch = window.matchMedia("(pointer: coarse)");
    this.bind();
  },

  // The block is drawn afresh when the choices change
  updated() {
    if (this.trigger && this.el.contains(this.trigger)) return;
    this.unbind();
    this.bind();
  },

  destroyed() {
    this.unbind();
  },

  bind() {
    this.trigger = this.el.querySelector("[data-combobox-trigger]");
    this.panel = this.el.querySelector("[data-combobox-panel]");
    this.input = this.el.querySelector("[data-combobox-input]");
    this.empty = this.el.querySelector("[data-combobox-empty]");
    if (!this.trigger || !this.panel) return;

    this.onTrigger = () => (this.panel.hidden ? this.open() : this.close());
    this.onInput = () => this.filter();
    this.onKey = (event) => this.key(event);
    this.onPick = (event) => {
      const option = event.target.closest("[data-combobox-option]");
      if (!option) return;
      if (option.getAttribute("aria-disabled") === "true") {
        event.preventDefault();
        return;
      }
      // Let the link or button do its job, then close
      setTimeout(() => this.close(), 0);
    };
    this.onOutside = (event) => {
      if (!this.el.contains(event.target)) this.close();
    };
    this.onMove = () => this.place();

    this.trigger.addEventListener("click", this.onTrigger);
    this.input.addEventListener("input", this.onInput);
    this.input.addEventListener("keydown", this.onKey);
    this.panel.addEventListener("click", this.onPick);
  },

  unbind() {
    this.close();
    this.trigger?.removeEventListener("click", this.onTrigger);
    this.input?.removeEventListener("input", this.onInput);
    this.input?.removeEventListener("keydown", this.onKey);
    this.panel?.removeEventListener("click", this.onPick);
  },

  options() {
    return Array.from(this.panel.querySelectorAll("[data-combobox-option]"));
  },

  visible() {
    return this.options().filter((option) => !option.hidden);
  },

  open() {
    this.panel.hidden = false;
    this.trigger.setAttribute("aria-expanded", "true");
    this.input.value = "";
    this.filter();
    this.place();
    // On touch screens the keyboard would cover the choices: people tap
    // the search box when they want it
    if (!this.touch.matches) this.input.focus({ preventScroll: true });
    document.addEventListener("pointerdown", this.onOutside, true);
    window.addEventListener("resize", this.onMove);
    window.addEventListener("scroll", this.onMove, true);
  },

  close() {
    if (!this.panel || this.panel.hidden) return;
    this.panel.hidden = true;
    this.trigger.setAttribute("aria-expanded", "false");
    document.removeEventListener("pointerdown", this.onOutside, true);
    window.removeEventListener("resize", this.onMove);
    window.removeEventListener("scroll", this.onMove, true);
  },

  // Under the button (or above it when there's more room there), as wide
  // as the button or at least 260px, never off the screen
  place() {
    if (this.panel.hidden) return;
    const rect = this.trigger.getBoundingClientRect();
    const margin = 8;
    const width = Math.min(
      Math.max(rect.width, 260),
      window.innerWidth - 2 * margin,
    );
    const left = Math.min(
      Math.max(rect.left, margin),
      window.innerWidth - width - margin,
    );
    const below = window.innerHeight - rect.bottom - margin;
    const above = rect.top - margin;
    const style = this.panel.style;

    style.left = `${left}px`;
    style.width = `${width}px`;
    if (below >= 240 || below >= above) {
      style.top = `${rect.bottom + 4}px`;
      style.bottom = "auto";
      style.maxHeight = `${Math.max(below - 4, 160)}px`;
    } else {
      style.top = "auto";
      style.bottom = `${window.innerHeight - rect.top + 4}px`;
      style.maxHeight = `${Math.max(above - 4, 160)}px`;
    }
  },

  filter() {
    const query = normalize(this.input.value.trim());
    this.options().forEach((option) => {
      option.hidden =
        query !== "" && !normalize(option.dataset.search).includes(query);
    });
    // A group's heading shows only while one of its choices does
    this.panel.querySelectorAll("[data-combobox-group]").forEach((heading) => {
      const group = heading.dataset.comboboxGroup;
      heading.hidden = !this.options().some(
        (option) => option.dataset.group === group && !option.hidden,
      );
    });
    this.empty.hidden = this.visible().length > 0;
    this.activate(this.visible()[0]);
  },

  activate(option) {
    this.options().forEach((o) =>
      o.toggleAttribute("data-active", o === option),
    );
    if (option) {
      this.input.setAttribute("aria-activedescendant", option.id);
      option.scrollIntoView({ block: "nearest" });
    } else {
      this.input.removeAttribute("aria-activedescendant");
    }
  },

  key(event) {
    const visible = this.visible();
    const current = visible.findIndex((o) => o.hasAttribute("data-active"));

    if (event.key === "ArrowDown" || event.key === "ArrowUp") {
      event.preventDefault();
      if (visible.length === 0) return;
      const step = event.key === "ArrowDown" ? 1 : -1;
      this.activate(
        visible[(current + step + visible.length) % visible.length],
      );
    } else if (event.key === "Enter") {
      event.preventDefault();
      const option = visible[current];
      if (option && option.getAttribute("aria-disabled") !== "true")
        option.click();
    } else if (event.key === "Escape") {
      event.preventDefault();
      this.close();
      this.trigger.focus();
    }
  },
};
