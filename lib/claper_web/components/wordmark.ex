defmodule ClaperWeb.Wordmark do
  @moduledoc """
  The organization's name and mark, from the Brand page (`Claper.Branding`,
  docs/BRAND.md). Drawn in the current text color, so they show on light and
  dark themes alike; set the color with a text class.

      <ClaperWeb.Wordmark.mark size={:md} class="text-base-content" />
      <ClaperWeb.Wordmark.mark short size={:sm} class="text-faint" />

  - With an uploaded logo (or mark, for `short`), the image is used as a
    mask over `currentColor`: its shape, in the theme's text color.
  - Without one, the name (or its monogram) is set in type.

  Sizes come from `--wm-h` (`size` sets it; `.brand-lockup` sets its own), so
  images and type line up the same way (assets/css/panels.css).
  """
  use Phoenix.Component

  alias Claper.Branding

  attr :short, :boolean, default: false, doc: "the mark (or monogram) instead of the full name"
  attr :size, :atom, default: :md, values: [:sm, :md, :lg, :none]
  attr :class, :any, default: nil
  attr :label, :string, default: nil, doc: "for screen readers; the brand's name by default"

  attr :brand, :any,
    default: nil,
    doc:
      "the brand to draw; the current one by default. Pass it where it can change on the page (the Brand page), so LiveView redraws it"

  def mark(assigns) do
    brand = assigns.brand || Branding.get()

    {src, text} =
      if assigns.short,
        do: {brand.mark_src, Branding.monogram(brand)},
        else: {brand.logo_src, Branding.name(brand)}

    assigns =
      assign(assigns,
        src: src,
        text: text,
        label: assigns.label || Branding.name(brand)
      )

    ~H"""
    <span
      role={if @label != "", do: "img"}
      aria-label={if @label != "", do: @label}
      aria-hidden={if @label == "", do: "true"}
      class={["wordmark", @size != :none && "wordmark-#{@size}", @class]}
    >
      <%= if @src do %>
        <img src={@src} alt="" class="wordmark-sizer" />
        <span class="wordmark-ink" style={"--wm-src: url('#{@src}')"}></span>
      <% else %>
        <span class="wordmark-text">{@text}</span>
      <% end %>
    </span>
    """
  end

  @doc """
  The brand lockup (2026-11-14): a softly glassy pill holding the mark in a
  round, top-lit tile and the name, in theme colors. Its size follows
  `--brand-h` (set by the class, e.g. `.brand-lockup-lg` on the big screen).
  Used at the top of the phone intro page and the big-screen join page.
  """
  attr :class, :string, default: nil
  attr :brand, :any, default: nil, doc: "as for mark/1"

  def lockup(assigns) do
    brand = assigns.brand || Branding.get()
    assigns = assign(assigns, brand: brand, label: Branding.name(brand))

    ~H"""
    <div class={["brand-lockup", @class]} role="img" aria-label={@label}>
      <span class="brand-lockup-tile" aria-hidden="true">
        <.mark short size={:none} class="brand-lockup-monogram" label="" brand={@brand} />
      </span>
      <.mark size={:none} class="brand-lockup-name" label="" brand={@brand} />
    </div>
    """
  end
end
