defmodule ClaperWeb.Component.Badge do
  @moduledoc """
  Badges: small labels (status, counts, an event's code). Looks are defined
  once in assets/css/badges.css (shadcn/ui style, theme colors); this module
  only picks the classes. See docs/THEME.md.

  - `badge/1`: `style` :primary (white), :secondary / :default / :neutral
    (gray), :ghost, :destructive, :success, :warning, :info; `type: :outlined`
    gives the outline look.
  - `event_code/1`: an event's join code, always the same everywhere:
    outline, "#CODE" in capitals.
  """
  use ClaperWeb, :view_component

  attr :type, :atom, default: :contained, values: [:contained, :outlined]

  attr :style, :atom,
    default: :default,
    values: [
      :default,
      :neutral,
      :primary,
      :secondary,
      :accent,
      :ghost,
      :destructive,
      :success,
      :warning,
      :info
    ]

  attr :size, :atom, default: :xs, values: [:xs, :sm, :md, :lg]
  attr :class, :string, default: nil
  attr :rest, :global

  slot :inner_block, required: true

  def badge(assigns) do
    ~H"""
    <span
      class={[
        base_classes(),
        size_classes(@size),
        style_classes(@type, @style),
        @class
      ]}
      {@rest}
    >
      {render_slot(@inner_block)}
    </span>
    """
  end

  attr :code, :string, required: true
  attr :class, :string, default: nil

  def event_code(assigns) do
    ~H"""
    <span class={["badge badge-outline font-mono tracking-wide", @class]}>
      #{String.upcase(@code)}
    </span>
    """
  end

  defp base_classes, do: "badge"

  defp size_classes(:xs), do: "badge-sm"
  defp size_classes(:sm), do: "badge-sm"
  defp size_classes(:md), do: nil
  defp size_classes(:lg), do: "badge-lg"

  defp style_classes(:outlined, _style), do: "badge-outline"
  defp style_classes(:contained, :primary), do: "badge-primary"
  defp style_classes(:contained, :ghost), do: "badge-ghost"
  defp style_classes(:contained, :destructive), do: "badge-error"
  defp style_classes(:contained, :accent), do: "badge-success"
  defp style_classes(:contained, :success), do: "badge-success"
  defp style_classes(:contained, :warning), do: "badge-warning"
  defp style_classes(:contained, :info), do: "badge-info"
  defp style_classes(:contained, _gray), do: "badge-secondary"
end
