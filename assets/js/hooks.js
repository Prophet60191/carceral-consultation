// LiveView hooks for client-side functionality

import WordCloud from "./word_cloud.mjs";
import { themeColor } from "./theme.js";

// Flash messages are toasts now (toaster.js); ClaperWeb.Component.Alert is
// only used inline, beside a form, and stays until the form is fixed.

const Hooks = {
  // Hook for handling CSV downloads from LiveView
  CSVDownloader: {
    mounted() {
      this.handleEvent("download_csv", ({ filename, content }) => {
        // Create a Blob with the CSV content
        const blob = new Blob([content], { type: "text/csv" });
        
        // Create a temporary URL for the Blob
        const url = window.URL.createObjectURL(blob);
        
        // Create a temporary link element
        const link = document.createElement("a");
        link.href = url;
        link.setAttribute("download", filename);
        
        // Append the link to the document body
        document.body.appendChild(link);
        
        // Trigger the download
        link.click();
        
        // Clean up
        window.URL.revokeObjectURL(url);
        document.body.removeChild(link);
      });
    }
  },
  
  // Hook for User Growth Chart
  UserGrowthChart: {
    mounted() {
      // Import Chart.js dynamically
      import("chart.js/auto").then(({ default: Chart }) => {
        const ctx = this.el.getContext("2d");
        const labels = JSON.parse(this.el.dataset.labels);
        const values = JSON.parse(this.el.dataset.values);
        
        this.chart = new Chart(ctx, {
          type: "line",
          data: {
            labels: labels,
            datasets: [{
              label: "New Users",
              data: values,
              borderColor: themeColor("chart-1"),
              backgroundColor: themeColor("chart-1", 0.1),
              borderWidth: 2,
              tension: 0.4,
              fill: true,
              pointRadius: 0,
              pointHoverRadius: 0,
              pointBackgroundColor: "transparent",
              pointBorderColor: "transparent"
            }]
          },
          options: {
            responsive: true,
            maintainAspectRatio: false,
            interaction: {
              intersect: false,
              mode: 'index'
            },
            plugins: {
              legend: {
                display: false
              },
              tooltip: {
                enabled: true,
                backgroundColor: themeColor("base-300"),
                titleColor: themeColor("base-content"),
                bodyColor: themeColor("base-content"),
                borderColor: themeColor("line"),
                borderWidth: 1,
                cornerRadius: 4,
                displayColors: false,
                padding: 8,
                titleFont: {
                  size: 12
                },
                bodyFont: {
                  size: 14,
                  weight: 'bold'
                },
                callbacks: {
                  label: function(context) {
                    return context.parsed.y + ' users';
                  }
                }
              }
            },
            scales: {
              x: {
                display: false
              },
              y: {
                display: false
              }
            }
          }
        });
      });
    },
    
    destroyed() {
      if (this.chart) {
        this.chart.destroy();
      }
    }
  },
  
  // Persists the event list view mode in a cookie so the server renders it on first paint
  ViewModePreference: {
    mounted() {
      this.handleEvent("save-view-mode", ({ view }) => {
        document.cookie = `claper_event_view_mode=${view}; path=/; max-age=31536000; SameSite=Lax`;
      });
    }
  },

  // Hook for Event Creation Chart
  EventCreationChart: {
    mounted() {
      // Import Chart.js dynamically
      import("chart.js/auto").then(({ default: Chart }) => {
        const ctx = this.el.getContext("2d");
        const labels = JSON.parse(this.el.dataset.labels);
        const values = JSON.parse(this.el.dataset.values);
        
        this.chart = new Chart(ctx, {
          type: "line",
          data: {
            labels: labels,
            datasets: [{
              label: "New Events",
              data: values,
              borderColor: themeColor("chart-1"),
              backgroundColor: themeColor("chart-1", 0.1),
              borderWidth: 2,
              tension: 0.4,
              fill: true,
              pointRadius: 0,
              pointHoverRadius: 0,
              pointBackgroundColor: "transparent",
              pointBorderColor: "transparent"
            }]
          },
          options: {
            responsive: true,
            maintainAspectRatio: false,
            interaction: {
              intersect: false,
              mode: 'index'
            },
            plugins: {
              legend: {
                display: false
              },
              tooltip: {
                enabled: true,
                backgroundColor: themeColor("base-300"),
                titleColor: themeColor("base-content"),
                bodyColor: themeColor("base-content"),
                borderColor: themeColor("line"),
                borderWidth: 1,
                cornerRadius: 4,
                displayColors: false,
                padding: 8,
                titleFont: {
                  size: 12
                },
                bodyFont: {
                  size: 14,
                  weight: 'bold'
                },
                callbacks: {
                  label: function(context) {
                    return context.parsed.y + ' events';
                  }
                }
              }
            },
            scales: {
              x: {
                display: false
              },
              y: {
                display: false
              }
            }
          }
        });
      });
    },
    
    destroyed() {
      if (this.chart) {
        this.chart.destroy();
      }
    }
  },

  WordCloud,

  // Breakout timer (docs/BREAKOUT.md, decision 18): counts down to the
  // ISO time in data-ends-at and shows "Time's up" at zero. It only
  // signals; nothing locks. The server re-renders data-ends-at when time is
  // added, and updated() picks it up.
  // The big screen's live intro results (docs/INTRO.md, decision 14): one
  // interaction at a time, moving on every 12 seconds, with dots. The place
  // is kept when the results refresh.
  IntroCarousel: {
    mounted() {
      this.index = 0;
      this.show();
      this.timer = window.setInterval(() => {
        this.index += 1;
        this.show();
      }, 12000);
    },
    updated() {
      this.show();
    },
    destroyed() {
      window.clearInterval(this.timer);
    },
    show() {
      const slides = [...this.el.querySelectorAll("[data-slide]")];
      if (slides.length === 0) return;
      this.index = this.index % slides.length;
      slides.forEach((slide, i) => (slide.hidden = i !== this.index));
      this.el
        .querySelectorAll("[data-dot]")
        .forEach((dot, i) => (dot.dataset.active = String(i === this.index)));
    },
  },

  // The big screen's countdown to the event's scheduled start (join screen,
  // before the presenter starts the event): "Starts in 1:05:32", then
  // "Starting soon". Text templates come from the server (translated).
  StartCountdown: {
    mounted() {
      this.render();
      this.timer = window.setInterval(() => this.render(), 1000);
    },
    updated() {
      this.render();
    },
    destroyed() {
      window.clearInterval(this.timer);
    },
    render() {
      const startsAt = Date.parse(this.el.dataset.startsAt || "");
      const left = Number.isNaN(startsAt) ? 0 : Math.round((startsAt - Date.now()) / 1000);
      if (left <= 0) {
        this.el.textContent = this.el.dataset.soon || "Starting soon";
        return;
      }
      const d = Math.floor(left / 86400);
      const h = Math.floor((left % 86400) / 3600);
      const m = Math.floor((left % 3600) / 60);
      const s = String(left % 60).padStart(2, "0");
      const hm = h > 0 || d > 0 ? `${h}:${String(m).padStart(2, "0")}` : `${m}`;
      const time = (d > 0 ? `${d}d ` : "") + `${hm}:${s}`;
      this.el.textContent = (this.el.dataset.in || "Starts in %{time}").replace("%{time}", time);
    },
  },

  BreakoutCountdown: {
    mounted() {
      this.render();
      this.timer = window.setInterval(() => this.render(), 1000);
    },
    updated() {
      this.render();
    },
    destroyed() {
      window.clearInterval(this.timer);
    },
    render() {
      const endsAt = Date.parse(this.el.dataset.endsAt || "");
      const label = this.el.querySelector("[data-countdown-text]") || this.el;
      if (Number.isNaN(endsAt)) {
        label.textContent = "";
        return;
      }
      const left = Math.max(0, Math.round((endsAt - Date.now()) / 1000));
      if (left === 0) {
        label.textContent = this.el.dataset.timesUp || "Time's up";
        this.el.dataset.state = "up";
      } else {
        const m = Math.floor(left / 60);
        const s = String(left % 60).padStart(2, "0");
        label.textContent = `${m}:${s}`;
        // The last minute: phones pulse red (.countdown-alert, Jose 2026-11-14).
        this.el.dataset.state = left <= 60 ? "ending" : "running";
      }
    },
  },
  // A drop-down menu that floats above the page (position: fixed) under its
  // button (above it only when there is little room below), as wide as its
  // anchor (data-anchor) and no taller than the window, so a scrolling panel around it can't cut it off. The button
  // dispatches "cc:place-menu" when it opens the menu; the menu closes when
  // anything around it scrolls or the window resizes, since it would no
  // longer line up.
  FloatingMenu: {
    mounted() {
      // Measured on the next frame, once the menu is shown and has a height.
      this.place = () => window.requestAnimationFrame(() => this.placeNow());
      this.placeNow = () => {
        if (getComputedStyle(this.el).display === "none") return;
        const anchor = document.querySelector(this.el.dataset.anchor);
        const button = document.querySelector(this.el.dataset.button);
        if (!anchor || !button) return;
        const a = anchor.getBoundingClientRect();
        const b = button.getBoundingClientRect();
        this.el.style.left = `${a.left}px`;
        this.el.style.width = `${a.width}px`;
        this.el.style.maxHeight = "none";
        const needed = this.el.scrollHeight;
        const below = window.innerHeight - b.bottom - 12;
        const above = b.top - 12;
        // Below the button, as drop-downs usually open, scrolling inside
        // itself if it is taller than the room there; above it only when
        // there is too little room below to be useful.
        if (needed <= below || below >= 280 || below >= above) {
          this.el.style.top = `${b.bottom + 4}px`;
          this.el.style.maxHeight = `${Math.max(160, below)}px`;
        } else {
          const height = Math.min(needed, above);
          this.el.style.top = `${b.top - 4 - height}px`;
          this.el.style.maxHeight = `${height}px`;
        }
      };
      this.close = (e) => {
        if (e && e.target instanceof Node && this.el.contains(e.target)) return;
        if (getComputedStyle(this.el).display !== "none") {
          this.liveSocket.execJS(this.el, `[["hide",{"to":"#${this.el.id}"}]]`);
        }
      };
      this.el.addEventListener("cc:place-menu", this.place);
      // Any scroll (the panel, or the page on phones) except inside the menu.
      document.addEventListener("scroll", this.close, { capture: true, passive: true });
      window.addEventListener("resize", this.close);
    },
    updated() {
      this.place();
    },
    destroyed() {
      document.removeEventListener("scroll", this.close, { capture: true });
      window.removeEventListener("resize", this.close);
    },
  },

  // A button that copies data-url to the clipboard and says "Copied" for a
  // moment (ClaperWeb.Component.CopyButton). The app runs on plain http on the home network, where browsers
  // block navigator.clipboard, so it falls back to a hidden text field and
  // copy command, and as a last resort shows the link to copy by hand.
  CopyLink: {
    mounted() {
      this.onClick = () => this.copy();
      this.el.addEventListener("click", this.onClick);
    },
    destroyed() {
      window.clearTimeout(this.timer);
    },
    async copy() {
      const text = this.el.dataset.url;
      let copied = false;
      if (navigator.clipboard && window.isSecureContext) {
        try {
          await navigator.clipboard.writeText(text);
          copied = true;
        } catch (_e) {
          copied = false;
        }
      }
      if (!copied) {
        const field = document.createElement("textarea");
        field.value = text;
        field.setAttribute("readonly", "");
        field.style.position = "fixed";
        field.style.opacity = "0";
        document.body.appendChild(field);
        field.select();
        try {
          copied = document.execCommand("copy");
        } catch (_e) {
          copied = false;
        }
        field.remove();
      }
      if (!copied) {
        window.prompt(this.el.dataset.prompt || "Copy this:", text);
        return;
      }
      const label = this.el.querySelector("[data-copy-label]");
      if (!label) return;
      label.textContent = this.el.dataset.copied || "Copied";
      window.clearTimeout(this.timer);
      this.timer = window.setTimeout(() => {
        label.textContent = this.el.dataset.label || "URL";
      }, 2000);
    },
  },
};

export default Hooks;
