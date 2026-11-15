defmodule ClaperWeb.ThemeScript do
  @moduledoc """
  Light / dark theme (Carceral Consultation, 2026-11-13).

  - `script/1` goes in the <head> of every page layout. It reads the saved
    choice ("dark", "light" or "system") from this browser's localStorage and
    sets <html data-theme> before the page draws, so there is no flash of the
    wrong theme. "system" follows the device's light/dark setting, live.
  - `switcher/1` is the Dark | Light | System button group in the account
    menu. Clicking sends a `cc:set-theme` event; assets/js/theme.js saves the
    choice and applies it.

  The choice is per device (this browser), not per account.
  """
  use Phoenix.Component
  use Gettext, backend: ClaperWeb.Gettext
  alias Phoenix.LiveView.JS

  # Kept as one exact string: the Content-Security-Policy allows this inline
  # script by its SHA-256 hash (`csp_hash/0`, ClaperWeb.Plugs.SecurityHeaders),
  # so the text that reaches the browser must not change by a single byte.
  @boot_js """
  (function () {
    var KEY = "cc-theme";
    function apply() {
      var choice = "dark";
      try { choice = localStorage.getItem(KEY) || "dark"; } catch (e) {}
      var light = choice === "light" ||
        (choice === "system" && window.matchMedia("(prefers-color-scheme: light)").matches);
      document.documentElement.setAttribute("data-theme", light ? "carceral-light" : "carceral");
      document.documentElement.setAttribute("data-theme-choice", choice);
    }
    apply();
    window.matchMedia("(prefers-color-scheme: light)").addEventListener("change", apply);
    window.__ccApplyTheme = apply;
  })();
  """

  @csp_hash "'sha256-" <> Base.encode64(:crypto.hash(:sha256, @boot_js)) <> "'"

  @doc "The Content-Security-Policy source that allows the theme script."
  def csp_hash, do: @csp_hash

  def script(assigns) do
    assigns = assign(assigns, :html, Phoenix.HTML.raw("<script>" <> @boot_js <> "</script>"))

    ~H"""
    {@html}
    """
  end

  def switcher(assigns) do
    assigns =
      assign(assigns, :choices, [
        {"dark", gettext("Dark")},
        {"light", gettext("Light")},
        {"system", gettext("System")}
      ])

    ~H"""
    <div class="px-3 py-2">
      <p class="mb-1.5 text-xs font-medium text-muted">{gettext("Theme")}</p>
      <div
        class={[ClaperWeb.Component.Tabs.segmented_group_class(), "w-full"]}
        role="group"
        aria-label={gettext("Theme")}
      >
        <button
          :for={{value, label} <- @choices}
          type="button"
          data-theme-option={value}
          phx-click={JS.dispatch("cc:set-theme", detail: %{theme: value})}
          class={[
            "flex-1 px-2 text-xs font-medium",
            ClaperWeb.Component.Tabs.segmented_item_class(false)
          ]}
        >
          {label}
        </button>
      </div>
    </div>
    """
  end
end
