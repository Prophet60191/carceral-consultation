defmodule ClaperWeb.Component.Switch do
  @moduledoc """
  On/off switches, modeled on shadcn/ui's Switch ("base-nova" style).
  (Carceral Consultation, 2026-11-13.) The look lives in
  assets/css/buttons.css (`.switch`, `.switch-sm`, `.switch-card`); this module
  is the one place switch markup is written. See docs/THEME.md.

  - `switch/1`: the switch alone.
  - `switch_row/1`: shadcn's "choice card": a bordered row with an optional
    icon, a title, an optional description, an optional keyboard shortcut
    and the switch. The whole row is a label, so tapping anywhere on it
    flips the switch. When on, the row is faintly highlighted.

  ## Examples

      <.switch checked={@on} phx-click="toggle" aria-label="Captions" />

      <ClaperWeb.Component.Switch.switch_row
        label={gettext("Show messages on big screen")}
        description={gettext("Attendees see each other's messages")}
        checked={@state.chat_visible}
        key={:chat_visible}
        shortcut="W"
      >
        <:icon>...</:icon>
      </ClaperWeb.Component.Switch.switch_row>
  """
  use Phoenix.Component

  attr :checked, :boolean, required: true
  attr :size, :atom, default: :default, values: [:default, :sm]
  attr :disabled, :boolean, default: false
  attr :class, :string, default: nil

  attr :rest, :global,
    include: ~w(phx-click phx-value-key phx-key phx-window-keydown phx-target aria-label
                aria-labelledby aria-invalid id name value form)

  def switch(assigns) do
    ~H"""
    <button
      type="button"
      role="switch"
      aria-checked={to_string(@checked)}
      disabled={@disabled}
      class={["switch", @size == :sm && "switch-sm", @class]}
      {@rest}
    >
    </button>
    """
  end

  attr :label, :string, required: true
  attr :description, :string, default: nil
  attr :checked, :boolean, required: true
  attr :key, :atom, required: true, doc: "the setting this row turns on and off"
  attr :shortcut, :string, default: nil
  attr :show_shortcut, :boolean, default: true
  attr :disabled, :boolean, default: false
  slot :icon

  def switch_row(assigns) do
    ~H"""
    <%!-- The label wraps the switch, so it is tied to it without an id
         (this row can appear twice on a page). --%>
    <label class="switch-card">
      <div
        :if={@icon != []}
        class="flex items-center justify-center size-8 rounded-md shrink-0 bg-base-300 text-base-content"
      >
        {render_slot(@icon)}
      </div>
      <div class="flex min-w-0 flex-1 flex-col gap-0.5 leading-snug">
        <span class="text-sm font-medium text-base-content">{@label}</span>
        <span :if={@description} class="text-sm text-muted">{@description}</span>
      </div>
      <kbd :if={@show_shortcut && @shortcut} class="kbd kbd-sm shrink-0">{@shortcut}</kbd>
      <.switch
        checked={@checked}
        disabled={@disabled}
        aria-label={@label}
        phx-click={ClaperWeb.Component.Input.checked(@checked, @key)}
        phx-value-key={@key}
        phx-key={@shortcut}
        phx-window-keydown={
          if @shortcut && not @disabled, do: ClaperWeb.Component.Input.checked(@checked, @key)
        }
      />
    </label>
    """
  end
end
