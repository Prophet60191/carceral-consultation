defmodule ClaperWeb.EventLive.ManageInteractionListComponent do
  use ClaperWeb, :live_component

  @per_page 6
  @max_per_page 20
  @fixed_content_height 200
  @interaction_row_height 64

  def update(assigns, socket) do
    page = Map.get(socket.assigns, :page, 0)
    per_page = Map.get(socket.assigns, :per_page, @per_page)
    total = length(assigns.interactions)
    max_page = max_page(total, per_page)
    page = min(page, max_page)

    {:ok,
     socket
     |> assign(assigns)
     |> assign(page: page, per_page: per_page)}
  end

  def handle_event("prev-page", _, socket) do
    {:noreply, assign(socket, page: max(0, socket.assigns.page - 1))}
  end

  def handle_event("next-page", _, socket) do
    max_page = max_page(length(socket.assigns.interactions), socket.assigns.per_page)
    {:noreply, assign(socket, page: min(max_page, socket.assigns.page + 1))}
  end

  def handle_event("interaction-list-resized", %{"height" => height}, socket)
      when is_integer(height) do
    per_page =
      height
      |> Kernel.-(@fixed_content_height)
      |> div(@interaction_row_height)
      |> max(@per_page)
      |> min(@max_per_page)

    first_interaction = socket.assigns.page * socket.assigns.per_page

    page =
      min(
        div(first_interaction, per_page),
        max_page(length(socket.assigns.interactions), per_page)
      )

    {:noreply, assign(socket, page: page, per_page: per_page)}
  end

  defp paginated_interactions(interactions, page, per_page) do
    interactions
    |> Enum.drop(page * per_page)
    |> Enum.take(per_page)
  end

  defp max_page(total, per_page), do: max(0, ceil(total / per_page) - 1)

  def render(assigns) do
    assigns =
      assign(assigns,
        paginated: paginated_interactions(assigns.interactions, assigns.page, assigns.per_page),
        total_pages: max(1, ceil(length(assigns.interactions) / assigns.per_page))
      )

    ~H"""
    <div
      id="interaction-drag-list"
      phx-hook="InteractionDrag"
      phx-target={@myself}
      class="panel relative lg:flex-1 lg:min-h-0 lg:overflow-y-auto"
    >
      <div class="panel-header">
        <svg
          xmlns="http://www.w3.org/2000/svg"
          width="24"
          height="24"
          viewBox="0 0 24 24"
          fill="none"
          stroke="currentColor"
          stroke-width="2"
          stroke-linecap="round"
          stroke-linejoin="round"
          class="icon icon-tabler icons-tabler-outline icon-tabler-north-star shrink-0 text-base-content"
        >
          <path stroke="none" d="M0 0h24v24H0z" fill="none" />
          <path d="M3 12h18" />
          <path d="M12 21v-18" />
          <path d="M7.5 7.5l9 9" />
          <path d="M7.5 16.5l9 -9" />
        </svg>
        <span class="font-bold text-sm text-base-content">{gettext("Interactions")}</span>
      </div>

      <div class="grid grid-cols-4 gap-1">
        <.action_button patch={~p"/e/#{@event_code}/manage/add/poll"} label={gettext("Poll")}>
          <svg
            xmlns="http://www.w3.org/2000/svg"
            class="h-5 w-5"
            fill="none"
            viewBox="0 0 24 24"
            stroke="currentColor"
            stroke-width="2"
          >
            <path
              stroke-linecap="round"
              stroke-linejoin="round"
              d="M16 8v8m-4-5v5m-4-2v2m-2 4h12a2 2 0 002-2V6a2 2 0 00-2-2H6a2 2 0 00-2 2v12a2 2 0 002 2z"
            />
          </svg>
        </.action_button>
        <.action_button patch={~p"/e/#{@event_code}/manage/add/form"} label={gettext("Form")}>
          <svg
            xmlns="http://www.w3.org/2000/svg"
            class="h-5 w-5"
            fill="none"
            viewBox="0 0 24 24"
            stroke="currentColor"
            stroke-width="2"
          >
            <path
              stroke-linecap="round"
              stroke-linejoin="round"
              d="M9 5H7a2 2 0 00-2 2v12a2 2 0 002 2h10a2 2 0 002-2V7a2 2 0 00-2-2h-2M9 5a2 2 0 002 2h2a2 2 0 002-2M9 5a2 2 0 012-2h2a2 2 0 012 2m-3 7h3m-3 4h3m-6-4h.01M9 16h.01"
            />
          </svg>
        </.action_button>
        <.action_button patch={~p"/e/#{@event_code}/manage/add/quiz"} label={gettext("Quiz")}>
          <svg
            xmlns="http://www.w3.org/2000/svg"
            class="h-5 w-5"
            fill="none"
            viewBox="0 0 24 24"
            stroke-width="2"
            stroke="currentColor"
          >
            <path
              stroke-linecap="round"
              stroke-linejoin="round"
              d="M9.879 7.519c1.171-1.025 3.071-1.025 4.242 0 1.172 1.025 1.172 2.687 0 3.712-.203.179-.43.326-.67.442-.745.361-1.45.999-1.45 1.827v.75M21 12a9 9 0 1 1-18 0 9 9 0 0 1 18 0Zm-9 5.25h.008v.008H12v-.008Z"
            />
          </svg>
        </.action_button>

        <div class="static">
          <button
            id="interaction-more-button"
            phx-click={
              JS.toggle(to: "#interaction-more-menu")
              |> JS.dispatch("cc:place-menu", to: "#interaction-more-menu")
            }
            aria-haspopup="menu"
            class="btn btn-ghost btn-stacked w-full"
          >
            <svg
              xmlns="http://www.w3.org/2000/svg"
              class="h-5 w-5 text-primary"
              fill="none"
              viewBox="0 0 24 24"
              stroke="currentColor"
              stroke-width="2"
            >
              <path
                stroke-linecap="round"
                stroke-linejoin="round"
                d="M12 6.75a.75.75 0 110-1.5.75.75 0 010 1.5zM12 12.75a.75.75 0 110-1.5.75.75 0 010 1.5zM12 18.75a.75.75 0 110-1.5.75.75 0 010 1.5z"
              />
            </svg>
            <span class="font-bold text-xs leading-normal">{gettext("More")}</span>
          </button>

          <%!-- Floats above the page (FloatingMenu hook), so the scrolling
               Interactions panel never cuts it off (Jose, 2026-11-14) --%>
          <div
            id="interaction-more-menu"
            role="menu"
            phx-hook="FloatingMenu"
            data-anchor="#interaction-drag-list"
            data-button="#interaction-more-button"
            phx-click-away={JS.hide(to: "#interaction-more-menu")}
            class="hidden fixed bg-base-200 border border-line rounded-2xl p-2 shadow-lg z-50 overflow-y-auto"
          >
            <%!-- Reorder this slide's interactions (Jose, 2026-11-14); handled by
                 the manage page, which owns the dialog --%>
            <button
              type="button"
              id="open-reorder"
              phx-click={JS.hide(to: "#interaction-more-menu") |> JS.push("open-reorder")}
              disabled={length(@interactions) < 2}
              class="menu-item w-full items-start p-2 text-left"
            >
              <div class="flex items-center justify-center w-9 h-9 rounded-full bg-selected text-primary shrink-0">
                <svg
                  xmlns="http://www.w3.org/2000/svg"
                  class="h-5 w-5"
                  fill="none"
                  viewBox="0 0 24 24"
                  stroke-width="2"
                  stroke="currentColor"
                  aria-hidden="true"
                >
                  <path
                    stroke-linecap="round"
                    stroke-linejoin="round"
                    d="M3 7.5 7.5 3m0 0L12 7.5M7.5 3v13.5m13.5 0L16.5 21m0 0L12 16.5m4.5 4.5V7.5"
                  />
                </svg>
              </div>
              <div class="min-w-0">
                <p class="font-bold text-sm text-base-content leading-snug">{gettext("Reorder")}</p>
                <p class="text-xs text-muted leading-tight">
                  {if length(@interactions) < 2,
                    do: gettext("Add a second interaction to this slide to reorder."),
                    else: gettext("Change the order of this slide's interactions.")}
                </p>
              </div>
            </button>
            <div class="my-1 border-t border-line" role="separator"></div>
            <.popup_item
              patch={~p"/e/#{@event_code}/manage/add/poll"}
              title={gettext("Poll")}
              description={gettext("Add a poll to gauge your audience's opinion.")}
            >
              <svg
                xmlns="http://www.w3.org/2000/svg"
                class="h-5 w-5"
                fill="none"
                viewBox="0 0 24 24"
                stroke="currentColor"
                stroke-width="2"
              >
                <path
                  stroke-linecap="round"
                  stroke-linejoin="round"
                  d="M16 8v8m-4-5v5m-4-2v2m-2 4h12a2 2 0 002-2V6a2 2 0 00-2-2H6a2 2 0 00-2 2v12a2 2 0 002 2z"
                />
              </svg>
            </.popup_item>
            <.popup_item
              patch={~p"/e/#{@event_code}/manage/add/form"}
              title={gettext("Form")}
              description={gettext("Create a form to collect feedback from your audience.")}
            >
              <svg
                xmlns="http://www.w3.org/2000/svg"
                class="h-5 w-5"
                fill="none"
                viewBox="0 0 24 24"
                stroke="currentColor"
                stroke-width="2"
              >
                <path
                  stroke-linecap="round"
                  stroke-linejoin="round"
                  d="M9 5H7a2 2 0 00-2 2v12a2 2 0 002 2h10a2 2 0 002-2V7a2 2 0 00-2-2h-2M9 5a2 2 0 002 2h2a2 2 0 002-2M9 5a2 2 0 012-2h2a2 2 0 012 2m-3 7h3m-3 4h3m-6-4h.01M9 16h.01"
                />
              </svg>
            </.popup_item>
            <.popup_item
              patch={~p"/e/#{@event_code}/manage/add/embed"}
              title={gettext("Web Content")}
              description={gettext("Embed external web content into your presentation.")}
            >
              <svg
                xmlns="http://www.w3.org/2000/svg"
                class="h-5 w-5"
                fill="none"
                viewBox="0 0 24 24"
                stroke-width="2"
                stroke="currentColor"
              >
                <path
                  stroke-linecap="round"
                  stroke-linejoin="round"
                  d="M14.25 9.75L16.5 12l-2.25 2.25m-4.5 0L7.5 12l2.25-2.25M6 20.25h12A2.25 2.25 0 0020.25 18V6A2.25 2.25 0 0018 3.75H6A2.25 2.25 0 003.75 6v12A2.25 2.25 0 006 20.25z"
                />
              </svg>
            </.popup_item>
            <.popup_item
              patch={~p"/e/#{@event_code}/manage/add/quiz"}
              title={gettext("Quiz")}
              description={gettext("Test your audience's knowledge with a quiz.")}
            >
              <svg
                xmlns="http://www.w3.org/2000/svg"
                class="h-5 w-5"
                fill="none"
                viewBox="0 0 24 24"
                stroke-width="2"
                stroke="currentColor"
              >
                <path
                  stroke-linecap="round"
                  stroke-linejoin="round"
                  d="M9.879 7.519c1.171-1.025 3.071-1.025 4.242 0 1.172 1.025 1.172 2.687 0 3.712-.203.179-.43.326-.67.442-.745.361-1.45.999-1.45 1.827v.75M21 12a9 9 0 1 1-18 0 9 9 0 0 1 18 0Zm-9 5.25h.008v.008H12v-.008Z"
                />
              </svg>
            </.popup_item>
            <.popup_item
              navigate={~p"/e/#{@event_code}/breakouts/new"}
              title={gettext("Breakout")}
              description={
                gettext("Split the room into small groups, each with material and questions.")
              }
            >
              <ClaperWeb.BreakoutLive.Icons.breakout class="h-5 w-5" />
            </.popup_item>
            <.popup_item
              patch={~p"/e/#{@event_code}/manage/add/word_cloud"}
              title={gettext("Word Cloud")}
              description={gettext("Let your audience answer in their own words.")}
            >
              <svg
                xmlns="http://www.w3.org/2000/svg"
                class="h-5 w-5"
                fill="none"
                viewBox="0 0 24 24"
                stroke-width="2"
                stroke="currentColor"
              >
                <path
                  stroke-linecap="round"
                  stroke-linejoin="round"
                  d="M2.25 15a4.5 4.5 0 0 0 4.5 4.5H18a3.75 3.75 0 0 0 1.332-7.257 3 3 0 0 0-3.758-3.848 5.25 5.25 0 0 0-10.233 2.33A4.502 4.502 0 0 0 2.25 15Z"
                />
              </svg>
            </.popup_item>
            <.popup_item
              :if={@transcription_globally_enabled}
              patch={transcription_patch(@event_code, @transcription_config)}
              disabled={transcription_persisted?(@transcription_config)}
              badge={gettext("Global")}
              title={gettext("Transcription")}
              description={
                if transcription_persisted?(@transcription_config),
                  do: gettext("Already added to this presentation."),
                  else: gettext("Live transcribe presenter audio for your audience.")
              }
            >
              <svg
                xmlns="http://www.w3.org/2000/svg"
                class="h-5 w-5"
                fill="none"
                viewBox="0 0 24 24"
                stroke-width="2"
                stroke="currentColor"
              >
                <path
                  stroke-linecap="round"
                  stroke-linejoin="round"
                  d="M12 18.75a6 6 0 0 0 6-6v-1.5m-6 7.5a6 6 0 0 1-6-6v-1.5m6 7.5v3.75m-3.75 0h7.5M12 15.75a3 3 0 0 1-3-3V4.5a3 3 0 1 1 6 0v8.25a3 3 0 0 1-3 3Z"
                />
              </svg>
            </.popup_item>
          </div>
        </div>
      </div>

      <div
        :if={@transcription_globally_enabled and transcription_persisted?(@transcription_config)}
        class="switch-card overflow-hidden"
      >
        <div class="flex-1 min-w-0">
          <div class="flex items-center gap-2">
            <span class="truncate text-sm font-medium text-base-content">
              {gettext("Transcription")}
            </span>
            <span class="badge badge-sm badge-soft badge-primary">{gettext("Global")}</span>
          </div>
          <span class="block truncate text-xs text-muted">
            {transcription_subtitle(@transcription_config)}
          </span>
        </div>

        <.link
          patch={~p"/e/#{@event_code}/manage/edit/transcription/#{@transcription_config.id}"}
          class="btn btn-ghost btn-square btn-sm"
          aria-label={gettext("Edit")}
        >
          <svg
            xmlns="http://www.w3.org/2000/svg"
            width="20"
            height="20"
            viewBox="0 0 20 20"
            fill="none"
          >
            <path
              d="M3.33301 17.4998H16.6663M4.72134 10.989C4.36602 11.3451 4.16643 11.8276 4.16634 12.3306V14.9998H6.85217C7.35551 14.9998 7.83801 14.7998 8.19384 14.4431L16.1105 6.52229C16.4657 6.16612 16.6652 5.68364 16.6652 5.18063C16.6652 4.67761 16.4657 4.19513 16.1105 3.83896L15.3288 3.05563C15.1526 2.87925 14.9432 2.73935 14.7129 2.64393C14.4825 2.54851 14.2355 2.49943 13.9862 2.49951C13.7368 2.49959 13.4899 2.54882 13.2596 2.64438C13.0292 2.73995 12.82 2.87998 12.6438 3.05646L4.72134 10.989Z"
              stroke="currentColor"
              stroke-width="1.5"
              stroke-linecap="round"
              stroke-linejoin="round"
            />
          </svg>
        </.link>

        <input
          type="checkbox"
          class="switch"
          checked={@transcription_config.enabled}
          phx-click={
            if(@transcription_config.enabled,
              do: "transcription-set-inactive",
              else: "transcription-set-active"
            )
          }
          phx-value-id={@transcription_config.id}
        />
      </div>

      <div
        :if={length(@interactions) == 0}
        class="flex flex-col items-center justify-center text-muted py-8"
      >
        <svg
          xmlns="http://www.w3.org/2000/svg"
          viewBox="0 0 24 24"
          fill="none"
          stroke="currentColor"
          stroke-width="2"
          stroke-linecap="round"
          stroke-linejoin="round"
          class="h-12 w-12 mb-3"
        >
          <path stroke="none" d="M0 0h24v24H0z" fill="none" /><path d="M4 12h6l-6 8h6" /><path d="M14 4h6l-6 8h6" />
        </svg>
        <p class="text-sm text-center">
          {gettext("No interactions on this slide")}
        </p>
      </div>

      <%= for interaction <- @paginated do %>
        <div
          draggable="true"
          data-interaction-id={interaction.id}
          data-interaction-type={type_key(interaction)}
          data-interaction-position={interaction.position}
          class="switch-card overflow-hidden cursor-grab active:cursor-grabbing"
        >
          <div class="flex min-w-0 flex-1 flex-col gap-0.5 leading-snug">
            <span class="truncate text-sm font-medium text-base-content">{interaction.title}</span>
            <span class="truncate text-xs text-muted">{type_label(interaction)}</span>
          </div>

          <.link
            patch={!breakout?(interaction) && edit_path(@event_code, interaction)}
            navigate={breakout?(interaction) && edit_path(@event_code, interaction)}
            draggable="false"
            class="btn btn-ghost btn-square btn-sm"
            aria-label={gettext("Edit")}
          >
            <svg
              xmlns="http://www.w3.org/2000/svg"
              width="20"
              height="20"
              viewBox="0 0 20 20"
              fill="none"
            >
              <path
                d="M3.33301 17.4998H16.6663M4.72134 10.989C4.36602 11.3451 4.16643 11.8276 4.16634 12.3306V14.9998H6.85217C7.35551 14.9998 7.83801 14.7998 8.19384 14.4431L16.1105 6.52229C16.4657 6.16612 16.6652 5.68364 16.6652 5.18063C16.6652 4.67761 16.4657 4.19513 16.1105 3.83896L15.3288 3.05563C15.1526 2.87925 14.9432 2.73935 14.7129 2.64393C14.4825 2.54851 14.2355 2.49943 13.9862 2.49951C13.7368 2.49959 13.4899 2.54882 13.2596 2.64438C13.0292 2.73995 12.82 2.87998 12.6438 3.05646L4.72134 10.989Z"
                stroke="currentColor"
                stroke-width="1.5"
                stroke-linecap="round"
                stroke-linejoin="round"
              />
            </svg>
          </.link>

          <%!-- A breakout is started from its live page, not switched on here. --%>
          <.link
            :if={breakout?(interaction)}
            navigate={~p"/e/#{@event_code}/breakouts/#{interaction.id}/live"}
            draggable="false"
            class={[
              "btn btn-sm",
              interaction.running && "btn-success",
              !interaction.running && "btn-primary"
            ]}
          >
            {if interaction.running, do: gettext("Live"), else: gettext("Start")}
          </.link>
          <input
            :if={!breakout?(interaction)}
            type="checkbox"
            class="switch"
            checked={interaction.enabled}
            phx-click={toggle_event(interaction)}
            phx-value-id={interaction.id}
          />
        </div>
      <% end %>

      <div :if={@total_pages > 1} class="flex items-center justify-between pt-1">
        <button
          phx-click="prev-page"
          phx-target={@myself}
          disabled={@page == 0}
          class="btn btn-ghost btn-square btn-xs text-muted"
        >
          <svg
            xmlns="http://www.w3.org/2000/svg"
            class="h-4 w-4"
            fill="none"
            viewBox="0 0 24 24"
            stroke="currentColor"
            stroke-width="2"
          >
            <path stroke-linecap="round" stroke-linejoin="round" d="M15 19l-7-7 7-7" />
          </svg>
        </button>
        <span class="text-xs text-muted">
          {@page + 1} / {@total_pages}
        </span>
        <button
          phx-click="next-page"
          phx-target={@myself}
          disabled={@page >= @total_pages - 1}
          class="btn btn-ghost btn-square btn-xs text-muted"
        >
          <svg
            xmlns="http://www.w3.org/2000/svg"
            class="h-4 w-4"
            fill="none"
            viewBox="0 0 24 24"
            stroke="currentColor"
            stroke-width="2"
          >
            <path stroke-linecap="round" stroke-linejoin="round" d="M9 5l7 7-7 7" />
          </svg>
        </button>
      </div>
    </div>
    """
  end

  defp type_key(interaction), do: Claper.Interactions.type_key(interaction)

  defp breakout?(%Claper.Breakouts.Breakout{}), do: true
  defp breakout?(_), do: false

  @doc "The kind of an interaction, in words (also used by the Reorder dialog)."
  def type_label(%Claper.Polls.Poll{}), do: gettext("Poll")
  def type_label(%Claper.Forms.Form{}), do: gettext("Form")
  def type_label(%Claper.Embeds.Embed{}), do: gettext("Web content")
  def type_label(%Claper.Quizzes.Quiz{}), do: gettext("Quiz")
  def type_label(%Claper.WordClouds.WordCloud{}), do: gettext("Word Cloud")
  def type_label(%Claper.Breakouts.Breakout{}), do: gettext("Breakout")
  def type_label(_), do: ""

  defp edit_path(event_code, %Claper.Polls.Poll{id: id}),
    do: ~p"/e/#{event_code}/manage/edit/poll/#{id}"

  defp edit_path(event_code, %Claper.Forms.Form{id: id}),
    do: ~p"/e/#{event_code}/manage/edit/form/#{id}"

  defp edit_path(event_code, %Claper.Embeds.Embed{id: id}),
    do: ~p"/e/#{event_code}/manage/edit/embed/#{id}"

  defp edit_path(event_code, %Claper.Quizzes.Quiz{id: id}),
    do: ~p"/e/#{event_code}/manage/edit/quiz/#{id}"

  defp edit_path(event_code, %Claper.WordClouds.WordCloud{id: id}),
    do: ~p"/e/#{event_code}/manage/edit/word_cloud/#{id}"

  defp edit_path(event_code, %Claper.Breakouts.Breakout{id: id}),
    do: ~p"/e/#{event_code}/breakouts/#{id}"

  defp edit_path(event_code, _), do: ~p"/e/#{event_code}/manage"

  defp toggle_event(%Claper.Polls.Poll{enabled: true}), do: "poll-set-inactive"
  defp toggle_event(%Claper.Polls.Poll{enabled: false}), do: "poll-set-active"
  defp toggle_event(%Claper.Forms.Form{enabled: true}), do: "form-set-inactive"
  defp toggle_event(%Claper.Forms.Form{enabled: false}), do: "form-set-active"
  defp toggle_event(%Claper.Embeds.Embed{enabled: true}), do: "embed-set-inactive"
  defp toggle_event(%Claper.Embeds.Embed{enabled: false}), do: "embed-set-active"
  defp toggle_event(%Claper.Quizzes.Quiz{enabled: true}), do: "quiz-set-inactive"
  defp toggle_event(%Claper.Quizzes.Quiz{enabled: false}), do: "quiz-set-active"
  defp toggle_event(%Claper.WordClouds.WordCloud{enabled: true}), do: "word-cloud-set-inactive"
  defp toggle_event(%Claper.WordClouds.WordCloud{enabled: false}), do: "word-cloud-set-active"
  defp toggle_event(_), do: ""

  defp transcription_patch(event_code, %Claper.Transcriptions.TranscriptionConfig{id: id})
       when not is_nil(id),
       do: ~p"/e/#{event_code}/manage/edit/transcription/#{id}"

  defp transcription_patch(event_code, _),
    do: ~p"/e/#{event_code}/manage/add/transcription"

  defp transcription_subtitle(%Claper.Transcriptions.TranscriptionConfig{enabled: true}),
    do: gettext("Live")

  defp transcription_subtitle(_), do: gettext("Disabled")

  defp transcription_persisted?(%Claper.Transcriptions.TranscriptionConfig{id: id})
       when not is_nil(id),
       do: true

  defp transcription_persisted?(_), do: false

  defp action_button(assigns) do
    ~H"""
    <.link patch={@patch} class="btn btn-ghost btn-stacked">
      <div class="text-primary">
        {render_slot(@inner_block)}
      </div>
      <span class="font-bold text-xs leading-normal">{@label}</span>
    </.link>
    """
  end

  defp popup_item(assigns) do
    assigns =
      assigns
      |> assign_new(:disabled, fn -> false end)
      |> assign_new(:badge, fn -> nil end)

    ~H"""
    <%= if @disabled do %>
      <div class="menu-item items-start p-2" aria-disabled="true" aria-disabled="true">
        <div class="flex items-center justify-center w-9 h-9 rounded-full bg-selected text-primary shrink-0">
          {render_slot(@inner_block)}
        </div>
        <div class="min-w-0">
          <div class="flex items-center gap-2">
            <p class="font-bold text-sm text-base-content leading-snug">{@title}</p>
            <span :if={@badge} class="badge badge-sm badge-soft badge-primary">{@badge}</span>
          </div>
          <p class="text-xs text-muted leading-tight">{@description}</p>
        </div>
      </div>
    <% else %>
      <.link patch={assigns[:patch]} navigate={assigns[:navigate]} class="menu-item items-start p-2">
        <div class="flex items-center justify-center w-9 h-9 rounded-full bg-selected text-primary shrink-0">
          {render_slot(@inner_block)}
        </div>
        <div class="min-w-0">
          <div class="flex items-center gap-2">
            <p class="font-bold text-sm text-base-content leading-snug">{@title}</p>
            <span :if={@badge} class="badge badge-sm badge-soft badge-primary">{@badge}</span>
          </div>
          <p class="text-xs text-muted leading-tight">{@description}</p>
        </div>
      </.link>
    <% end %>
    """
  end
end
