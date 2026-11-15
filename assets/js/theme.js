// Theme colors for scripts (Carceral Consultation, 2026-11-13).
//
// Colors are defined once, in assets/css/theme-config.css. Scripts that must
// hand a color to a library (charts, QR codes, the page-load bar) read it from
// the page's CSS variables here instead of writing a color value.
// See docs/THEME.md.

/** Theme color for a role, e.g. themeColor("base-content") or themeColor("line", 0.5). */
export function themeColor(role, alpha = 1) {
  const value = getComputedStyle(document.documentElement)
    .getPropertyValue(`--color-${role}`)
    .trim();
  if (!value) {
    console.warn(`[theme] unknown color role: ${role}`);
    return "transparent";
  }
  if (alpha >= 1) return value;
  // Canvas libraries (Chart.js) want plain rgba(), so expand #rrggbb ourselves.
  const hex = value.match(/^#([0-9a-f]{2})([0-9a-f]{2})([0-9a-f]{2})$/i);
  if (hex) {
    const [r, g, b] = hex.slice(1).map((h) => parseInt(h, 16));
    return `rgba(${r}, ${g}, ${b}, ${alpha})`;
  }
  return `color-mix(in srgb, ${value} ${Math.round(alpha * 100)}%, transparent)`;
}

// Theme switcher (Dark | Light | System in the account menu). The choice is
// saved in this browser and applied by the script in each page's <head>
// (ClaperWeb.ThemeScript). Charts read their colors when they draw, so they
// pick up a new theme on the next page load.
const THEME_KEY = "cc-theme";

function markThemeOptions() {
  let choice = "dark";
  try {
    choice = localStorage.getItem(THEME_KEY) || "dark";
  } catch (_e) {}
  document.querySelectorAll("[data-theme-option]").forEach((btn) => {
    const on = btn.dataset.themeOption === choice;
    btn.setAttribute("aria-pressed", String(on));
    btn.classList.toggle("bg-selected", on);
  });
}

export function initThemeSwitcher() {
  window.addEventListener("cc:set-theme", (e) => {
    try {
      localStorage.setItem(THEME_KEY, e.detail.theme);
    } catch (_e) {}
    if (window.__ccApplyTheme) window.__ccApplyTheme();
    markThemeOptions();
  });
  // Menus are re-rendered by LiveView; keep the pressed state right, at
  // most once per frame (busy pages such as live chat change constantly).
  let queued = false;
  const schedule = () => {
    if (queued) return;
    queued = true;
    requestAnimationFrame(() => {
      queued = false;
      markThemeOptions();
    });
  };
  window.addEventListener("phx:page-loading-stop", schedule);
  document.addEventListener("DOMContentLoaded", schedule);
  new MutationObserver(schedule).observe(document.documentElement, {
    childList: true,
    subtree: true,
  });
}
