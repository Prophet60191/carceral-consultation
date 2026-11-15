defmodule ClaperWeb.Component.Tabs do
  @moduledoc """
  DaisyUI-inspired Tabs component for Claper.

  ## Styles
  - `:bordered` - Simple tabs with bottom border on active (default)
  - `:lifted` - Lifted appearance with border on sides and top for active
  - `:boxed` - Pill-shaped tabs with background, active has primary fill
  - `:segmented` - Joined button group: one outline, thin dividers between
    buttons, the chosen one a shade lighter (Jose's pattern, 2026-11-13)

  ## Examples

      <.tabs>
        <:tab>Tab 1</:tab>
        <:tab active>Tab 2</:tab>
        <:tab>Tab 3</:tab>
      </.tabs>

      <.tabs style={:boxed}>
        <:tab>Home</:tab>
        <:tab active>Profile</:tab>
        <:tab>Settings</:tab>
      </.tabs>

      <.tabs style={:lifted}>
        <:tab>Overview</:tab>
        <:tab active>Details</:tab>
        <:tab>History</:tab>
      </.tabs>

  ## With click handlers

      <.tabs style={:boxed}>
        <:tab active={@active_tab == "home"} phx-click="set_tab" phx-value-tab="home">Home</:tab>
        <:tab active={@active_tab == "profile"} phx-click="set_tab" phx-value-tab="profile">Profile</:tab>
      </.tabs>
  """
  use ClaperWeb, :view_component

  attr :style, :atom, default: :bordered, values: [:bordered, :lifted, :boxed, :segmented]
  attr :class, :string, default: nil
  attr :rest, :global

  slot :tab, required: true do
    attr :active, :boolean
    attr :disabled, :boolean
    attr :class, :string
    attr :"phx-click", :string
    attr :"phx-target", :string
    attr :"phx-value-tab", :string
  end

  def tabs(assigns) do
    ~H"""
    <div
      role="tablist"
      class={[
        container_classes(@style),
        @class
      ]}
      {@rest}
    >
      <%= for {tab, _index} <- Enum.with_index(@tab) do %>
        <button
          role="tab"
          class={[
            tab_base_classes(@style),
            tab_state_classes(@style, tab[:active] || false),
            disabled_classes(tab[:disabled] || false)
          ]}
          aria-selected={tab[:active] || false}
          disabled={tab[:disabled] || false}
          {assigns_to_attributes(tab, [:active, :disabled, :class, :inner_block])}
        >
          {render_slot(tab)}
        </button>
      <% end %>
    </div>
    """
  end

  @doc """
  Renders a single tab item. Use this for more control over individual tabs.

  ## Examples

      <.tab_item active>Active Tab</.tab_item>
      <.tab_item phx-click="change_tab">Inactive Tab</.tab_item>
  """
  attr :style, :atom, default: :bordered, values: [:bordered, :lifted, :boxed, :segmented]
  attr :active, :boolean, default: false
  attr :disabled, :boolean, default: false
  attr :class, :string, default: nil
  attr :rest, :global, include: ~w(phx-click phx-target phx-value-tab)

  slot :inner_block, required: true

  def tab_item(assigns) do
    ~H"""
    <button
      role="tab"
      class={[
        tab_base_classes(@style),
        tab_state_classes(@style, @active),
        disabled_classes(@disabled),
        @class
      ]}
      aria-selected={@active}
      disabled={@disabled}
      {@rest}
    >
      {render_slot(@inner_block)}
    </button>
    """
  end

  # Container classes based on style
  defp container_classes(:bordered) do
    "flex items-center border-b border-line"
  end

  defp container_classes(:lifted) do
    "flex items-end"
  end

  defp container_classes(:boxed) do
    "inline-flex items-center bg-base-300 rounded-full"
  end

  defp container_classes(:segmented), do: segmented_group_class()

  # Base tab classes based on style
  defp tab_base_classes(:bordered) do
    "px-4 py-1.5 text-sm font-normal font-display transition-all duration-200 rounded-t-lg -mb-px"
  end

  defp tab_base_classes(:lifted) do
    "px-4 py-1.5 text-sm font-normal font-display transition-all duration-200 rounded-t-lg border-b border-line"
  end

  defp tab_base_classes(:boxed) do
    "px-5 py-3 text-sm font-normal font-display transition-all duration-200 rounded-full"
  end

  defp tab_base_classes(:segmented),
    do: "px-4 text-sm font-medium font-display whitespace-nowrap shrink-0"

  # Tab state classes (active/inactive) based on style
  defp tab_state_classes(:bordered, true) do
    "text-base-content border-b-2 border-line font-medium"
  end

  defp tab_state_classes(:bordered, false) do
    "text-muted hover:text-base-content border-b-2 border-transparent"
  end

  defp tab_state_classes(:lifted, true) do
    "text-base-content bg-base-200 border-l border-r border-t border-line border-b-0 -mb-px"
  end

  defp tab_state_classes(:lifted, false) do
    "text-muted hover:text-base-content bg-transparent"
  end

  defp tab_state_classes(:boxed, true) do
    "text-primary-content bg-primary font-semibold"
  end

  defp tab_state_classes(:boxed, false) do
    "text-muted hover:text-base-content bg-transparent"
  end

  defp tab_state_classes(:segmented, active), do: segmented_item_class(active)

  @doc """
  Classes for the segmented button-group look, for groups that are not plain
  text tabs (e.g. the grid/list toggle with icons). One source for the look.
  """
  def segmented_group_class do
    "inline-flex items-stretch h-9 pointer-coarse:h-11 rounded-lg border border-line bg-base-200 overflow-hidden divide-x divide-line"
  end

  def segmented_item_class(active) do
    [
      "transition-colors duration-150 focus:outline-none focus-visible:ring-2 focus-visible:ring-inset focus-visible:ring-primary",
      if(active, do: "bg-selected text-base-content", else: "text-base-content hover:bg-base-300")
    ]
  end

  # Disabled classes
  defp disabled_classes(true), do: "opacity-50 cursor-not-allowed"
  defp disabled_classes(false), do: "cursor-pointer"
end
