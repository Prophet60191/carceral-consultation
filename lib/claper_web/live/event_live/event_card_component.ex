defmodule ClaperWeb.EventLive.EventCardComponent do
  @moduledoc """
  One event on My events, in three layouts: grid, list and phone.
  (Carceral Consultation, 2026-11-13.) All three are built from the same
  pieces below (thumbnail, status badge, code badge, date line, actions with
  the Join menu, the more-options menu), so they look and behave alike.
  Cards use the panel standard; actions are always visible.
  """
  use ClaperWeb, :live_component

  alias Claper.Events.Event
  alias Claper.Presentations

  def render(assigns) do
    assigns =
      assigns
      |> assign_new(:is_leader, fn -> false end)
      |> assign_new(:view_mode, fn -> "grid" end)
      |> assign(:thumbnail_url, get_thumbnail_url(assigns.event))

    case assigns.view_mode do
      "grid" -> render_grid_card(assigns)
      "mobile" -> render_mobile_card(assigns)
      _ -> render_list_card(assigns)
    end
  end

  defp get_thumbnail_url(event) do
    Presentations.get_first_slide_url(event.presentation_file)
  end

  defp dom_id(component_id, suffix) do
    "#{component_id}-#{suffix}"
  end

  # ---- The three layouts ----

  defp render_grid_card(assigns) do
    ~H"""
    <div id={dom_id(@id, "card")} class="panel h-full gap-0 p-0">
      <.thumb
        event={@event}
        thumbnail_url={@thumbnail_url}
        class="aspect-video rounded-t-2xl border-b border-line"
      />
      <div class="flex flex-1 flex-col gap-3 p-3">
        <div class="flex items-start justify-between gap-3">
          <div class="min-w-0 flex-1">
            <.name_row event={@event} />
            <div :if={Event.started?(@event) == false or Event.finished?(@event)} class="mt-1">
              <.date_line event={@event} id={@id} />
            </div>
          </div>
          <.more_menu id={@id} event={@event} is_leader={@is_leader} myself={@myself} />
        </div>
        <div class="mt-auto">
          <.actions id={@id} event={@event} is_leader={@is_leader} stretch />
        </div>
      </div>
    </div>
    """
  end

  defp render_list_card(assigns) do
    ~H"""
    <div class="w-full" id={dom_id(@id, "card")}>
      <div class="panel flex-row items-center gap-4 p-3">
        <.thumb
          event={@event}
          thumbnail_url={@thumbnail_url}
          class="w-28 shrink-0 aspect-video rounded-lg border border-line"
        />
        <div class="min-w-0">
          <.name_row event={@event} />
          <div :if={Event.started?(@event) == false or Event.finished?(@event)} class="mt-1">
            <.date_line event={@event} id={@id} />
          </div>
        </div>
        <div class="ml-auto flex items-center gap-2">
          <.actions id={@id} event={@event} is_leader={@is_leader} align="right" />
          <.more_menu id={@id} event={@event} is_leader={@is_leader} myself={@myself} />
        </div>
      </div>
    </div>
    """
  end

  defp render_mobile_card(assigns) do
    ~H"""
    <div class="w-full" id={dom_id(@id, "card")}>
      <div class="panel gap-3 p-2">
        <div class="flex items-start gap-3">
          <.thumb
            event={@event}
            thumbnail_url={@thumbnail_url}
            class="w-28 shrink-0 aspect-video rounded-lg border border-line"
          />
          <div class="min-w-0 flex-1 py-0.5">
            <.name_row event={@event} />
          </div>
          <.more_menu id={@id} event={@event} is_leader={@is_leader} myself={@myself} />
        </div>
        <.actions id={@id} event={@event} is_leader={@is_leader} stretch />
      </div>
    </div>
    """
  end

  # ---- Shared pieces ----

  attr :event, :map, required: true
  attr :thumbnail_url, :string, default: nil
  attr :class, :string, default: nil

  defp thumb(assigns) do
    ~H"""
    <div class={["relative overflow-hidden bg-base-300", @class]}>
      <%= if @thumbnail_url do %>
        <img src={@thumbnail_url} alt={@event.name} class="h-full w-full object-cover" />
      <% else %>
        <div class="flex h-full w-full items-center justify-center">
          <ClaperWeb.Wordmark.mark short size={:sm} class="text-faint" />
        </div>
      <% end %>
      <div
        :if={@event.presentation_file.status == "progress"}
        class="absolute inset-0 flex flex-col items-center justify-center gap-2 bg-base-200/80 backdrop-blur-sm"
      >
        <ClaperWeb.Wordmark.mark short size={:sm} label="Loading" class="animate-pulse text-muted" />
        <span class="text-xs font-medium text-muted">{gettext("Processing...")}</span>
      </div>
    </div>
    """
  end

  attr :event, :map, required: true

  # Name, code and status on one line (Jose, 2026-11-13). When the line is
  # too narrow (phones), the badges wrap below rather than squeezing the
  # name; only a name longer than the whole line gets "...". Badges stay in
  # the text row, never over the slide (soft badges vanish on images).
  defp name_row(assigns) do
    ~H"""
    <div class="flex min-w-0 flex-wrap items-center gap-x-2 gap-y-1">
      <h3 class="max-w-full truncate font-semibold text-base-content">{@event.name}</h3>
      <ClaperWeb.Component.Badge.event_code code={@event.code} />
      <.status_badge event={@event} />
      <.lti_badge :if={@event.lti_resource} />
    </div>
    """
  end

  attr :event, :map, required: true

  defp status_badge(assigns) do
    ~H"""
    <span :if={Event.started?(@event) && !Event.finished?(@event)} class="badge badge-error">
      <span class="size-1.5 animate-pulse rounded-full bg-error"></span>
      {gettext("Live")}
    </span>
    <span :if={!Event.started?(@event) && !Event.finished?(@event)} class="badge badge-secondary">
      {gettext("Upcoming")}
    </span>
    <span :if={Event.finished?(@event)} class="badge badge-outline">
      {gettext("Finished")}
    </span>
    """
  end

  defp lti_badge(assigns) do
    ~H"""
    <span class="badge badge-secondary">
      <svg viewBox="0 0 20 20" fill="currentColor" aria-hidden="true">
        <path
          fill-rule="evenodd"
          d="M9.664 1.319a.75.75 0 0 1 .672 0 41.059 41.059 0 0 1 8.198 5.424.75.75 0 0 1-.254 1.285 31.372 31.372 0 0 0-7.86 3.83.75.75 0 0 1-.84 0 31.508 31.508 0 0 0-2.08-1.287V9.394c0-.244.116-.463.302-.592a35.504 35.504 0 0 1 3.305-2.033.75.75 0 0 0-.714-1.319 37 37 0 0 0-3.446 2.12A2.216 2.216 0 0 0 6 9.393v.38a31.293 31.293 0 0 0-4.28-1.746.75.75 0 0 1-.254-1.285 41.059 41.059 0 0 1 8.198-5.424ZM6 11.459a29.848 29.848 0 0 0-2.455-1.158 41.029 41.029 0 0 0-.39 3.114.75.75 0 0 0 .419.74c.528.256 1.046.53 1.554.82-.21.324-.455.63-.739.914a.75.75 0 1 0 1.06 1.06c.37-.369.69-.77.96-1.193a26.61 26.61 0 0 1 3.095 2.348.75.75 0 0 0 .992 0 26.547 26.547 0 0 1 5.93-3.95.75.75 0 0 0 .42-.739 41.053 41.053 0 0 0-.39-3.114 29.925 29.925 0 0 0-5.199 2.801 2.25 2.25 0 0 1-2.514 0c-.41-.275-.826-.541-1.25-.797a6.985 6.985 0 0 1-1.084 3.45 26.503 26.503 0 0 0-1.281-.78A5.487 5.487 0 0 0 6 12v-.54Z"
          clip-rule="evenodd"
        />
      </svg>
      LTI
    </span>
    """
  end

  attr :event, :map, required: true
  attr :id, :string, required: true

  defp date_line(assigns) do
    ~H"""
    <span
      :if={!Event.finished?(@event) && !Event.started?(@event)}
      id={dom_id(@id, "event-date")}
      class="text-xs text-muted"
    >
      {gettext("Starting on")}
      <time
        id={dom_id(@id, "local-start")}
        phx-hook="LocalDate"
        datetime={"#{NaiveDateTime.to_iso8601(@event.started_at)}Z"}
        data-utc={NaiveDateTime.to_iso8601(@event.started_at)}
        data-format="lll"
      >
        {@event.started_at} UTC
      </time>
    </span>
    <span :if={Event.finished?(@event)} id={dom_id(@id, "event-date")} class="text-xs text-muted">
      {gettext("Finished on")}
      <time
        id={dom_id(@id, "local-end")}
        phx-hook="LocalDate"
        datetime={"#{NaiveDateTime.to_iso8601(@event.expired_at)}Z"}
        data-utc={NaiveDateTime.to_iso8601(@event.expired_at)}
        data-format="lll"
      >
        {@event.expired_at} UTC
      </time>
    </span>
    """
  end

  # Open, End event, or View report: always visible.
  # `stretch` makes the buttons share the row (grid and phone cards).
  attr :id, :string, required: true
  attr :event, :map, required: true
  attr :is_leader, :boolean, default: false
  attr :stretch, :boolean, default: false
  attr :align, :string, default: "left", values: ["left", "right"]

  defp actions(assigns) do
    ~H"""
    <div class="flex items-center gap-2">
      <%= if @event.presentation_file.status == "done" && !Event.finished?(@event) do %>
        <%!-- Open goes straight to managing the event; the audience view and
             the rest are reached from there (Jose, 2026-11-15). --%>
        <a
          id={dom_id(@id, "open-button")}
          href={~p"/e/#{@event.code}/manage"}
          class={["btn btn-primary", @stretch && "flex-1"]}
        >
          <svg viewBox="0 0 20 20" fill="currentColor" aria-hidden="true">
            <path
              fill-rule="evenodd"
              d="M5.22 14.78a.75.75 0 001.06 0l7.22-7.22v5.69a.75.75 0 001.5 0v-7.5a.75.75 0 00-.75-.75h-7.5a.75.75 0 000 1.5h5.69l-7.22 7.22a.75.75 0 000 1.06z"
              clip-rule="evenodd"
            />
          </svg>
          {gettext("Open")}
        </a>
        <.link
          :if={Event.started?(@event) && not @is_leader}
          data-confirm-title={gettext("End this event?")}
          data-confirm={gettext("Attendees can no longer join or take part. This cannot be undone.")}
          data-confirm-action={gettext("End event")}
          data-confirm-icon="warning"
          data-confirm-variant="destructive"
          phx-value-id={@event.uuid}
          phx-click="terminate"
          class={["btn btn-outline", @stretch && "flex-1"]}
        >
          <svg viewBox="0 0 20 20" fill="currentColor" aria-hidden="true">
            <path d="M6.28 5.22a.75.75 0 0 0-1.06 1.06L8.94 10l-3.72 3.72a.75.75 0 1 0 1.06 1.06L10 11.06l3.72 3.72a.75.75 0 1 0 1.06-1.06L11.06 10l3.72-3.72a.75.75 0 0 0-1.06-1.06L10 8.94 6.28 5.22Z" />
          </svg>
          {gettext("End event")}
        </.link>
      <% end %>
      <span :if={@event.presentation_file.status == "fail"} class="badge badge-error">
        {gettext("Error when processing the file")}
      </span>
      <a
        :if={Event.finished?(@event)}
        href={~p"/events/#{@event.uuid}/stats"}
        class={["btn btn-primary", @stretch && "w-full"]}
      >
        <svg viewBox="0 0 20 20" fill="currentColor" aria-hidden="true">
          <path d="M2 10a8 8 0 018-8v8h8a8 8 0 11-16 0z" />
          <path d="M12 2.252A8.014 8.014 0 0117.748 8H12V2.252z" />
        </svg>
        {gettext("View report")}
      </a>
    </div>
    """
  end

  attr :id, :string, required: true
  attr :event, :map, required: true
  attr :is_leader, :boolean, default: false
  attr :myself, :any, required: true

  defp more_menu(assigns) do
    ~H"""
    <div :if={not @is_leader} class="relative shrink-0">
      <button
        type="button"
        aria-label={gettext("More options")}
        aria-haspopup="menu"
        phx-click-away={JS.hide(to: "##{dom_id(@id, "dropdown-menu")}")}
        phx-click={JS.toggle(to: "##{dom_id(@id, "dropdown-menu")}")}
        phx-target={@myself}
        class="btn btn-ghost btn-square btn-sm text-muted"
      >
        <svg fill="currentColor" viewBox="0 0 24 24" aria-hidden="true">
          <circle cx="12" cy="5" r="2" />
          <circle cx="12" cy="12" r="2" />
          <circle cx="12" cy="19" r="2" />
        </svg>
      </button>
      <div
        id={dom_id(@id, "dropdown-menu")}
        phx-hook="Dropdown"
        class="hidden absolute right-0 top-full z-30 mt-1 w-52 rounded-lg border border-line bg-base-200 p-1 shadow-lg"
      >
        {render_dropdown_menu(assigns)}
      </div>
    </div>
    """
  end

  defp render_dropdown_menu(assigns) do
    ~H"""
    <ul class="w-full">
      <%= if !Event.finished?(@event) && not @is_leader do %>
        <li>
          <.link patch={~p"/events/#{@event.uuid}/edit"} class="menu-item">
            <svg
              xmlns="http://www.w3.org/2000/svg"
              viewBox="0 0 20 20"
              fill="currentColor"
              class="w-5 h-5"
            >
              <path d="m5.433 13.917 1.262-3.155A4 4 0 0 1 7.58 9.42l6.92-6.918a2.121 2.121 0 0 1 3 3l-6.92 6.918c-.383.383-.84.685-1.343.886l-3.154 1.262a.5.5 0 0 1-.65-.65Z" />
              <path d="M3.5 5.75c0-.69.56-1.25 1.25-1.25H10A.75.75 0 0 0 10 3H4.75A2.75 2.75 0 0 0 2 5.75v9.5A2.75 2.75 0 0 0 4.75 18h9.5A2.75 2.75 0 0 0 17 15.25V10a.75.75 0 0 0-1.5 0v5.25c0 .69-.56 1.25-1.25 1.25h-9.5c-.69 0-1.25-.56-1.25-1.25v-9.5Z" />
            </svg>
            {gettext("Edit")}
          </.link>
        </li>
        <li>
          <button phx-value-id={@event.uuid} phx-click="duplicate" class="menu-item">
            <svg
              xmlns="http://www.w3.org/2000/svg"
              viewBox="0 0 20 20"
              fill="currentColor"
              class="w-5 h-5"
            >
              <path d="M7 3.5A1.5 1.5 0 0 1 8.5 2h3.879a1.5 1.5 0 0 1 1.06.44l3.122 3.12A1.5 1.5 0 0 1 17 6.622V12.5a1.5 1.5 0 0 1-1.5 1.5h-1v-3.379a3 3 0 0 0-.879-2.121L10.5 5.379A3 3 0 0 0 8.379 4.5H7v-1Z" />
              <path d="M4.5 6A1.5 1.5 0 0 0 3 7.5v9A1.5 1.5 0 0 0 4.5 18h7a1.5 1.5 0 0 0 1.5-1.5v-5.879a1.5 1.5 0 0 0-.44-1.06L9.44 6.439A1.5 1.5 0 0 0 8.378 6H4.5Z" />
            </svg>
            {gettext("Duplicate")}
          </button>
        </li>
      <% end %>

      <%= if Event.finished?(@event) && not @is_leader do %>
        <li>
          <button phx-value-id={@event.uuid} phx-click="duplicate" class="menu-item">
            <svg
              xmlns="http://www.w3.org/2000/svg"
              viewBox="0 0 20 20"
              fill="currentColor"
              class="w-5 h-5"
            >
              <path d="M7 3.5A1.5 1.5 0 0 1 8.5 2h3.879a1.5 1.5 0 0 1 1.06.44l3.122 3.12A1.5 1.5 0 0 1 17 6.622V12.5a1.5 1.5 0 0 1-1.5 1.5h-1v-3.379a3 3 0 0 0-.879-2.121L10.5 5.379A3 3 0 0 0 8.379 4.5H7v-1Z" />
              <path d="M4.5 6A1.5 1.5 0 0 0 3 7.5v9A1.5 1.5 0 0 0 4.5 18h7a1.5 1.5 0 0 0 1.5-1.5v-5.879a1.5 1.5 0 0 0-.44-1.06L9.44 6.439A1.5 1.5 0 0 0 8.378 6H4.5Z" />
            </svg>
            {gettext("Duplicate")}
          </button>
        </li>
        <li>
          <.link
            phx-click="delete"
            phx-value-id={@event.uuid}
            data-confirm-title={gettext("Delete this event?")}
            data-confirm={
              gettext("Its slides, interactions and answers are deleted. This cannot be undone.")
            }
            data-confirm-action={gettext("Delete")}
            data-confirm-variant="destructive"
            class="menu-item menu-item-error"
          >
            <svg
              xmlns="http://www.w3.org/2000/svg"
              viewBox="0 0 16 16"
              fill="currentColor"
              class="w-5 h-5"
            >
              <path
                fill-rule="evenodd"
                d="M5 3.25V4H2.75a.75.75 0 0 0 0 1.5h.3l.815 8.15A1.5 1.5 0 0 0 5.357 15h5.285a1.5 1.5 0 0 0 1.493-1.35l.815-8.15h.3a.75.75 0 0 0 0-1.5H11v-.75A2.25 2.25 0 0 0 8.75 1h-1.5A2.25 2.25 0 0 0 5 3.25Zm2.25-.75a.75.75 0 0 0-.75.75V4h3v-.75a.75.75 0 0 0-.75-.75h-1.5ZM6.05 6a.75.75 0 0 1 .787.713l.275 5.5a.75.75 0 0 1-1.498.075l-.275-5.5A.75.75 0 0 1 6.05 6Zm3.9 0a.75.75 0 0 1 .712.787l-.275 5.5a.75.75 0 0 1-1.498-.075l.275-5.5a.75.75 0 0 1 .786-.711Z"
                clip-rule="evenodd"
              />
            </svg>
            {gettext("Delete")}
          </.link>
        </li>
      <% end %>
    </ul>
    """
  end

  def handle_event("open", _params, socket) do
    {:noreply, socket |> assign(:dropdown, true)}
  end
end
