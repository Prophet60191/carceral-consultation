defmodule ClaperWeb.IntroLive.Components do
  @moduledoc """
  Drawing an intro page (docs/INTRO.md): `page/1` draws its blocks the way a
  participant's phone shows them; the builder's preview uses the same
  component, so what you build is what they see. Every block is drawn by the
  design system (decision 3), never by the author.
  """
  use Phoenix.Component
  use Gettext, backend: ClaperWeb.Gettext

  @doc """
  What a participant's phone shows until the presenter starts the event
  (docs/INTRO.md, step 3): the ticket with the event's name, date and the
  countdown to its scheduled start ("Starting soon" once that has passed),
  then the page's blocks. No QR code: whoever sees this is already in.
  With `close`, it is the "About this event" view over the slides.
  """
  attr :id, :string, required: true
  attr :event, :map, required: true
  attr :blocks, :list, required: true

  attr :countdown, :map,
    default: nil,
    doc: "days, hours, minutes, seconds; nil when the time has passed"

  attr :contents, :map, default: %{}, doc: "interaction blocks' content, by block id"
  attr :answers, :map, default: %{}, doc: "this phone's answers, by block id"
  attr :interactive, :boolean, default: false, doc: "whether the interactions can be answered"
  attr :banner_src, :string, default: nil
  attr :banner_alt, :string, default: nil
  attr :close, :string, default: nil, doc: "an event that closes this view (About this event)"

  def intro_screen(assigns) do
    ~H"""
    <div id={@id} class="ticket-stage intro-stage">
      <button :if={@close} type="button" phx-click={@close} class="btn btn-secondary self-end">
        {gettext("Back to the event")}
      </button>

      <%!-- The brand on top (Jose, 2026-11-14) --%>
      <ClaperWeb.Wordmark.lockup class="intro-brand" />

      <div class="ticket" id={"#{@id}-ticket"} phx-hook="TicketTilt">
        <div class="texture"></div>
        <div class="glare"></div>

        <img :if={@banner_src} src={@banner_src} alt={@banner_alt || ""} class="intro-banner" />

        <div class="ticket-body">
          <span class="eyebrow">
            <span class="dot"></span>{gettext("Live interactive event")}
          </span>

          <h1 class="event-title">{@event.name}</h1>

          <p
            id={"#{@id}-date"}
            class="event-date"
            phx-hook="LocalDate"
            data-utc={NaiveDateTime.to_iso8601(@event.started_at)}
            data-format="LLLL"
            data-capitalize="true"
          >
            {Calendar.strftime(@event.started_at, "%B %d, %Y %H:%M")}
          </p>

          <%!-- The countdown exactly as the waiting ticket had it (Jose) --%>
          <div :if={@countdown} class="cd-row">
            <%= for {{value, label}, i} <- Enum.with_index(countdown_cells(@countdown)) do %>
              <div :if={i > 0} class="cd-sep">:</div>
              <div class="cd-cell">
                <div class="cd-num">{if value < 10, do: "0"}{value}</div>
                <div class="cd-label">{label}</div>
              </div>
            <% end %>
          </div>
          <p :if={!@close and is_nil(@countdown)} class="intro-soon">
            {gettext("Starting soon")}
          </p>
        </div>
      </div>

      <section class="intro-blocks">
        <.page blocks={@blocks} contents={@contents} answers={@answers} interactive={@interactive} />
      </section>

      <a href="https://claper.co" target="_blank" class="powered-by">
        <span>{gettext("Powered by")}</span>
        <span>Claper</span>
      </a>
      <%!-- The license notices and source code (AGPL-3.0, section 13) --%>
      <a href="/about" target="_blank" rel="noopener" class="powered-by">
        {gettext("About this app")}
      </a>
    </div>
    """
  end

  defp countdown_cells(c) do
    [
      {c.days, gettext("days")},
      {c.hours, gettext("hours")},
      {c.minutes, gettext("minutes")},
      {c.seconds, gettext("seconds")}
    ]
  end

  attr :blocks, :list, required: true
  attr :contents, :map, default: %{}
  attr :answers, :map, default: %{}
  attr :interactive, :boolean, default: false

  def page(assigns) do
    assigns = assign(assigns, :sections, sections(assigns.blocks))

    ~H"""
    <%!-- Depth (docs/THEME.md, panels): each heading starts a card one step
         above the page; stats rise one more step, agendas sit inset. --%>
    <div class="flex flex-col gap-4 text-base-content">
      <section :for={section <- @sections} class="intro-section panel">
        <div class="flex flex-col gap-4 p-3">
          <.block
            :for={block <- section}
            block={block}
            contents={@contents}
            answers={@answers}
            interactive={@interactive}
          />
        </div>
      </section>
      <p :if={@blocks == []} class="text-center text-sm text-muted">
        {gettext("Nothing here yet.")}
      </p>
    </div>
    """
  end

  # Blocks grouped into sections: a heading starts a new one.
  defp sections(blocks) do
    blocks
    |> Enum.chunk_while(
      [],
      fn
        %{kind: "heading"} = block, [] -> {:cont, [block]}
        %{kind: "heading"} = block, acc -> {:cont, Enum.reverse(acc), [block]}
        block, acc -> {:cont, [block | acc]}
      end,
      fn
        [] -> {:cont, []}
        acc -> {:cont, Enum.reverse(acc), []}
      end
    )
  end

  attr :block, :map, required: true
  attr :contents, :map, default: %{}
  attr :answers, :map, default: %{}
  attr :interactive, :boolean, default: false

  # Interactions (decision 11) are drawn by the same component as on breakout
  # phones; their taps send intro_* events (IntroLive.Answering).
  def block(%{block: %{kind: kind}} = assigns)
      when kind in ["poll", "quiz", "form", "word_cloud", "embed"] do
    assigns = assign(assigns, :content, assigns.contents[assigns.block.id])

    ~H"""
    <div :if={@content} id={"intro-block-#{@block.id}"}>
      <ClaperWeb.BreakoutLive.Components.piece_input
        piece={@block}
        content={@content}
        response={@answers[@block.id]}
        editable={@interactive}
        events="intro"
      />
    </div>
    """
  end

  def block(%{block: %{kind: "heading"}} = assigns) do
    ~H"""
    <h2 class="text-2xl font-bold leading-tight">{@block.data["text"]}</h2>
    """
  end

  def block(%{block: %{kind: "text"}} = assigns) do
    ~H"""
    <p class="whitespace-pre-line text-base leading-relaxed" phx-no-format>{@block.data["body"]}</p>
    """
  end

  def block(%{block: %{kind: "image"}} = assigns) do
    ~H"""
    <figure class="flex flex-col gap-2">
      <img
        src={@block.data["src"]}
        alt={@block.data["alt"] || ""}
        class="w-full rounded-xl border border-line object-cover"
        loading="lazy"
      />
      <figcaption :if={@block.data["caption"] not in [nil, ""]} class="text-sm text-muted">
        {@block.data["caption"]}
      </figcaption>
    </figure>
    """
  end

  def block(%{block: %{kind: "stat"}} = assigns) do
    ~H"""
    <div class="flex flex-col gap-1 rounded-xl border border-line bg-base-300 p-4 shadow-md">
      <p class="text-4xl font-extrabold leading-none tabular-nums">{@block.data["value"]}</p>
      <p class="text-sm text-muted">{@block.data["label"]}</p>
    </div>
    """
  end

  def block(%{block: %{kind: "agenda"}} = assigns) do
    ~H"""
    <ol class="panel-inset flex flex-col divide-y divide-line">
      <li :for={item <- @block.data["items"] || []} class="flex gap-4 px-4 py-3">
        <span :if={item["time"] != ""} class="w-20 shrink-0 text-sm tabular-nums text-muted">
          {item["time"]}
        </span>
        <span class="text-base">{item["title"]}</span>
      </li>
    </ol>
    """
  end

  def block(%{block: %{kind: "link"}} = assigns) do
    ~H"""
    <a
      href={@block.data["url"]}
      target="_blank"
      rel="noopener noreferrer"
      class="btn btn-outline w-full"
    >
      {@block.data["label"]}
    </a>
    """
  end

  def block(%{block: %{kind: "divider"}} = assigns) do
    ~H"""
    <hr class="border-line" />
    """
  end

  @doc "A block kind in words."
  def kind_label("heading"), do: gettext("Heading")
  def kind_label("text"), do: gettext("Text")
  def kind_label("image"), do: gettext("Image")
  def kind_label("stat"), do: gettext("Stat")
  def kind_label("agenda"), do: gettext("Agenda")
  def kind_label("link"), do: gettext("Link")
  def kind_label("divider"), do: gettext("Divider")
  def kind_label("poll"), do: gettext("Poll")
  def kind_label("quiz"), do: gettext("Quiz")
  def kind_label("form"), do: gettext("Form")
  def kind_label("word_cloud"), do: gettext("Word cloud")
  def kind_label("embed"), do: gettext("Web content")

  @doc "A one-line summary of a block for the builder's list."
  def summary(%{kind: "heading", data: d}), do: d["text"]
  def summary(%{kind: "text", data: d}), do: d["body"]
  def summary(%{kind: "image", data: d}), do: d["caption"] || d["alt"] || ""
  def summary(%{kind: "stat", data: d}), do: "#{d["value"]} · #{d["label"]}"

  def summary(%{kind: "agenda", data: d}),
    do: ngettext("1 item", "%{count} items", length(d["items"] || []))

  def summary(%{kind: "link", data: d}), do: "#{d["label"]} · #{d["url"]}"
  def summary(%{kind: "divider"}), do: gettext("A line between sections")

  @icons %{
    "heading" => "M7.5 4.5v15m9-15v15M7.5 12h9",
    "text" => "M3.75 6.75h16.5M3.75 12h16.5m-16.5 5.25H12",
    "image" =>
      "m2.25 15.75 5.159-5.159a2.25 2.25 0 0 1 3.182 0l5.159 5.159m-1.5-1.5 1.409-1.409a2.25 2.25 0 0 1 3.182 0l2.909 2.909M3.75 21h16.5A2.25 2.25 0 0 0 22.5 18.75V5.25A2.25 2.25 0 0 0 20.25 3H3.75A2.25 2.25 0 0 0 1.5 5.25v13.5A2.25 2.25 0 0 0 3.75 21Z",
    "stat" =>
      "M3 13.125C3 12.504 3.504 12 4.125 12h2.25c.621 0 1.125.504 1.125 1.125v6.75C7.5 20.496 6.996 21 6.375 21h-2.25A1.125 1.125 0 0 1 3 19.875v-6.75ZM9.75 8.625c0-.621.504-1.125 1.125-1.125h2.25c.621 0 1.125.504 1.125 1.125v11.25c0 .621-.504 1.125-1.125 1.125h-2.25a1.125 1.125 0 0 1-1.125-1.125V8.625ZM16.5 4.125c0-.621.504-1.125 1.125-1.125h2.25C20.496 3 21 3.504 21 4.125v15.75c0 .621-.504 1.125-1.125 1.125h-2.25a1.125 1.125 0 0 1-1.125-1.125V4.125Z",
    "agenda" => "M12 6v6h4.5m4.5 0a9 9 0 1 1-18 0 9 9 0 0 1 18 0Z",
    "link" =>
      "M13.19 8.688a4.5 4.5 0 0 1 1.242 7.244l-4.5 4.5a4.5 4.5 0 0 1-6.364-6.364l1.757-1.757m13.35-.622 1.757-1.757a4.5 4.5 0 0 0-6.364-6.364l-4.5 4.5a4.5 4.5 0 0 0 1.242 7.244",
    "divider" => "M5 12h14"
  }

  attr :kind, :string, required: true
  attr :class, :string, default: "size-5"

  # Interactions use the same icons as everywhere else they appear.
  def icon(%{kind: kind} = assigns)
      when kind in ["poll", "quiz", "form", "word_cloud", "embed"] do
    ~H"""
    <ClaperWeb.BreakoutLive.Icons.piece kind={@kind} class={@class} />
    """
  end

  def icon(assigns) do
    assigns = assign(assigns, :d, Map.fetch!(@icons, assigns.kind))

    ~H"""
    <svg
      xmlns="http://www.w3.org/2000/svg"
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      stroke-width="1.5"
      class={@class}
      aria-hidden="true"
    >
      <path stroke-linecap="round" stroke-linejoin="round" d={@d} />
    </svg>
    """
  end
end
