defmodule ClaperWeb.EventLive.TakeHome do
  @moduledoc """
  The take-home page (docs/MATERIALS.md, Jose 2026-11-15): what phones show
  once the event ends, at `/e/:code/take-home`: the slides (if switched on)
  and the take-home PDFs switched on, each with a download button, with
  "Available until" at the top. After that time it says the materials are
  no longer available.

  People get here when the event ends while they're in the room
  (`EventLive.Show`), or by opening the event's link afterwards. A running
  event sends them back to the room.
  """
  use ClaperWeb, :live_view

  alias Claper.Materials

  on_mount(ClaperWeb.AttendeeLiveAuth)

  @impl true
  def mount(%{"code" => code}, session, socket) do
    with %{"locale" => locale} <- session do
      Gettext.put_locale(ClaperWeb.Gettext, locale)
    end

    cond do
      Claper.Events.get_event_with_code(code) ->
        {:ok, push_navigate(socket, to: ~p"/e/#{code}")}

      event = Materials.ended_event_with_code(code) ->
        if connected?(socket), do: Materials.subscribe(event)

        {:ok,
         socket
         |> assign(:page_title, event.name)
         |> assign(:code, code)
         |> load(event)}

      true ->
        {:ok,
         socket
         |> put_flash(:error, gettext("Event doesn't exist"))
         |> redirect(to: "/")}
    end
  end

  defp load(socket, event) do
    event = Claper.Repo.get!(Claper.Events.Event, event.id)
    now = NaiveDateTime.utc_now()
    until = Materials.take_home_until(event)

    socket
    |> assign(
      event: event,
      until: until,
      closed?: Materials.take_home_closed?(event, now),
      items: Materials.take_home_items(event, now)
    )
    |> schedule_close(until, now)
  end

  # Close the page on screen when its time comes: one timer, replaced
  # whenever the page reloads (the time may have been changed).
  defp schedule_close(socket, until, now) do
    if timer = socket.assigns[:close_timer], do: Process.cancel_timer(timer)
    ms = if until, do: NaiveDateTime.diff(until, now, :millisecond), else: 0

    timer =
      if connected?(socket) and ms > 0 and ms < 2_000_000_000,
        do: Process.send_after(self(), :closing_time, ms + 500)

    assign(socket, :close_timer, timer)
  end

  @impl true
  def handle_info(:materials_changed, socket), do: {:noreply, load(socket, socket.assigns.event)}
  def handle_info(:closing_time, socket), do: {:noreply, load(socket, socket.assigns.event)}
  def handle_info(_, socket), do: {:noreply, socket}

  @impl true
  def render(assigns) do
    ~H"""
    <main id="take-home" class="take-home font-display">
      <div class="mx-auto flex w-full max-w-lg flex-col gap-6 px-4 py-10">
        <header class="flex flex-col gap-1">
          <p class="text-xs font-bold uppercase tracking-wide text-muted">
            {gettext("To take home")}
          </p>
          <h1 class="text-2xl font-bold text-base-content">{@event.name}</h1>
          <p :if={@until && not @closed?} class="text-sm text-muted">
            {gettext("Available until")}
            <span
              id="take-home-until"
              phx-hook="LocalDate"
              data-utc={NaiveDateTime.to_iso8601(@until)}
              data-format="dddd, MMMM D, h:mm A"
            >
              {Calendar.strftime(@until, "%Y-%m-%d %H:%M UTC")}
            </span>
          </p>
        </header>

        <p :if={@closed?} id="take-home-closed" class="panel p-5 text-base-content">
          {gettext("The materials for this event are no longer available.")}
        </p>

        <p
          :if={not @closed? and not @items.slides? and @items.files == []}
          id="take-home-empty"
          class="panel p-5 text-base-content"
        >
          {gettext("This event has ended. There's nothing to take home from it.")}
        </p>

        <ul :if={not @closed?} class="flex flex-col gap-3">
          <li :if={@items.slides?} id="take-home-slides" class="take-home-item panel">
            <.item_body title={gettext("Slides")} detail={@event.name} />
            <a
              href={~p"/materials/slides/#{@event.uuid}"}
              download
              class="btn btn-primary"
              aria-label={gettext("Download the slides")}
            >
              <.download_icon /> {gettext("Download")}
            </a>
          </li>
          <li :for={file <- @items.files} id={"take-home-#{file.uuid}"} class="take-home-item panel">
            <.item_body
              title={file.title}
              detail={ClaperWeb.EventLive.MaterialsComponent.size(file.byte_size)}
            />
            <a
              href={~p"/materials/#{file.uuid}?download=1"}
              download
              class="btn btn-primary"
              aria-label={gettext("Download %{title}", title: file.title)}
            >
              <.download_icon /> {gettext("Download")}
            </a>
          </li>
        </ul>
      </div>

      <ClaperWeb.EventLive.Messenger.theme_button id="take-home-theme" />
    </main>
    """
  end

  attr :title, :string, required: true
  attr :detail, :string, required: true

  defp item_body(assigns) do
    ~H"""
    <div class="flex min-w-0 flex-1 items-center gap-3">
      <div class="flex size-10 shrink-0 items-center justify-center rounded-lg bg-base-300 text-base-content">
        <svg
          class="size-5"
          viewBox="0 0 24 24"
          fill="none"
          stroke="currentColor"
          stroke-width="1.8"
          stroke-linecap="round"
          stroke-linejoin="round"
          aria-hidden="true"
        >
          <path d="M14 3v4a1 1 0 0 0 1 1h4" />
          <path d="M17 21h-10a2 2 0 0 1 -2 -2v-14a2 2 0 0 1 2 -2h7l5 5v11a2 2 0 0 1 -2 2z" />
        </svg>
      </div>
      <div class="flex min-w-0 flex-col">
        <span class="truncate font-medium text-base-content">{@title}</span>
        <span class="truncate text-sm text-muted">{@detail}</span>
      </div>
    </div>
    """
  end

  defp download_icon(assigns) do
    ~H"""
    <svg class="size-4" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
      <path stroke-linecap="round" stroke-linejoin="round" d="M12 4v12m0 0-4-4m4 4 4-4M5 20h14" />
    </svg>
    """
  end
end
