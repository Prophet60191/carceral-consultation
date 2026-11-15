defmodule ClaperWeb.Component.Button do
  @moduledoc """
  DaisyUI-inspired Button component for Claper.

  ## Styles
  Looks are defined once, in assets/css/buttons.css (shadcn/ui style, theme
  colors). This component only picks the classes. See docs/THEME.md.
  - `:primary` - White button, dark text (default; the main action)
  - `:outline` - Thin border over a faint fill
  - `:secondary` - Quieter solid gray
  - `:ghost` - No fill until hovered
  - `:destructive` - Soft red tint, red text
  - `:link` - Looks like a link
  - `:neutral`, `:accent`, `:default` - kept for older calls; same as `:secondary`

  ## Sizes
  - `:xs` - 24px  `:sm` - 28px  `:md` - 32px (default)  `:lg` - 36px
  (On the audience's phone screens every button is at least 44px.)

  ## Shapes
  - `:square` - Standard rounded corners (default)
  - `:circle` - Fully rounded (pill shape)

  ## Examples

      <.button>Click me</.button>
      <.button style={:primary} size={:lg}>Large Primary</.button>
      <.button style={:ghost} shape={:circle}>Ghost Pill</.button>
      <.button disabled>Disabled</.button>
  """
  use ClaperWeb, :view_component

  attr :type, :string, default: "button"

  attr :style, :atom,
    default: :primary,
    values: [
      :primary,
      :outline,
      :secondary,
      :ghost,
      :destructive,
      :link,
      :neutral,
      :accent,
      :default
    ]

  attr :size, :atom, default: :md, values: [:xs, :sm, :md, :lg]
  attr :shape, :atom, default: :square, values: [:square, :circle]
  attr :disabled, :boolean, default: false
  attr :class, :string, default: nil

  attr :rest, :global,
    include: ~w(phx-click phx-target phx-disable-with phx-value-id form name value)

  slot :inner_block, required: true
  slot :icon_left
  slot :icon_right

  def button(assigns) do
    ~H"""
    <button
      type={@type}
      disabled={@disabled}
      class={[
        base_classes(),
        size_classes(@size),
        style_classes(@style),
        shape_classes(@shape, @size),
        disabled_classes(@disabled),
        @class
      ]}
      {@rest}
    >
      <%= if @icon_left != [] do %>
        <span class={icon_size_classes(@size)}>
          {render_slot(@icon_left)}
        </span>
      <% end %>
      <span class="truncate">{render_slot(@inner_block)}</span>
      <%= if @icon_right != [] do %>
        <span class={icon_size_classes(@size)}>
          {render_slot(@icon_right)}
        </span>
      <% end %>
    </button>
    """
  end

  attr :type, :string, default: "button"

  attr :style, :atom,
    default: :default,
    values: [
      :primary,
      :outline,
      :secondary,
      :ghost,
      :destructive,
      :link,
      :neutral,
      :accent,
      :default
    ]

  attr :size, :atom, default: :md, values: [:xs, :sm, :md, :lg]
  attr :shape, :atom, default: :square, values: [:square, :circle]
  attr :disabled, :boolean, default: false
  attr :class, :string, default: nil

  attr :rest, :global,
    include: ~w(phx-click phx-target phx-disable-with phx-value-id form name value)

  slot :inner_block, required: true

  def icon_button(assigns) do
    ~H"""
    <button
      type={@type}
      disabled={@disabled}
      class={[
        base_classes(),
        icon_button_size_classes(@size),
        style_classes(@style),
        icon_button_shape_classes(@shape),
        disabled_classes(@disabled),
        @class
      ]}
      {@rest}
    >
      <span class={icon_size_classes(@size)}>
        {render_slot(@inner_block)}
      </span>
    </button>
    """
  end

  defp base_classes, do: "btn"

  defp size_classes(:xs), do: "btn-xs"
  defp size_classes(:sm), do: "btn-sm"
  defp size_classes(:md), do: nil
  defp size_classes(:lg), do: "btn-lg"

  defp icon_button_size_classes(size), do: size_classes(size)

  # Icons inside buttons take the size set in buttons.css
  defp icon_size_classes(_size), do: "inline-flex shrink-0"

  defp style_classes(:primary), do: "btn-primary"
  defp style_classes(:outline), do: "btn-outline"
  defp style_classes(:secondary), do: "btn-secondary"
  defp style_classes(:ghost), do: "btn-ghost"
  defp style_classes(:destructive), do: "btn-error"
  defp style_classes(:link), do: "btn-link"
  defp style_classes(style) when style in [:neutral, :accent, :default], do: "btn-secondary"

  defp shape_classes(:square, _size), do: nil
  defp shape_classes(:circle, _size), do: "rounded-full"

  defp icon_button_shape_classes(:square), do: "btn-square"
  defp icon_button_shape_classes(:circle), do: "btn-circle"

  defp disabled_classes(true), do: "btn-disabled"
  defp disabled_classes(false), do: nil
end
