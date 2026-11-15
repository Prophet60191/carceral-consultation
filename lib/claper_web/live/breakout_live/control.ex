defmodule ClaperWeb.BreakoutLive.Control do
  @moduledoc """
  The presenter's control room for a breakout (docs/BREAKOUT.md, step 4),
  at `/e/<code>/breakouts/<id>/live`.

    * Before it starts: how many phones are connected and the groups that
      would make; Start.
    * While it runs: the timer with add-time, messages to every group or one
      group, a card per group (people, note-taker when its tasks need one,
      progress, answers), "Show on big screen" for reporting back, Stop.
    * After it stops: the results stay here; it can be started again.
  """
  use ClaperWeb, :live_view

  on_mount(ClaperWeb.UserLiveAuth)

  alias Claper.Breakouts
  alias Claper.Breakouts.{Live, Sorter}
  alias ClaperWeb.BreakoutLive.ViewData
  alias ClaperWeb.Presence

  @impl true
  def mount(%{"code" => code, "id" => id}, session, socket) do
    with %{"locale" => locale} <- session do
      Gettext.put_locale(ClaperWeb.Gettext, locale)
    end

    user = socket.assigns.current_user

    event =
      Claper.Events.get_event_with_code(code, [:user, presentation_file: :presentation_state])

    with %{} <- event,
         true <- Claper.Events.led_by?(user.email, event) || event.user.id == user.id,
         %{} = breakout <- Breakouts.get_breakout_for_presentation(id, event.presentation_file.id) do
      if connected?(socket), do: Claper.Events.Event.subscribe(event.uuid)

      {:ok,
       socket
       |> assign(event: event, breakout: breakout, page_title: breakout.title, notice: nil)
       |> assign(:message_form, to_form(%{"text" => "", "group" => ""}, as: :message))
       |> load()}
    else
      _ ->
        {:ok,
         socket
         |> put_flash(:error, gettext("Breakout not found"))
         |> redirect(to: ~p"/events")}
    end
  end

  defp load(socket) do
    breakout = Breakouts.get_breakout!(socket.assigns.breakout.id, [])
    run = Breakouts.open_run(breakout) || Breakouts.latest_run(breakout)
    connected = connected_people(socket.assigns.event)

    socket
    |> assign(:breakout, breakout)
    |> assign(:connected, length(connected))
    |> assign(:preview, Sorter.group_sizes(length(connected), sizing(breakout)))
    |> assign(:room, run && ViewData.room(run))
  end

  defp connected_people(event), do: Presence.list("event:#{event.uuid}") |> Map.keys()

  defp sizing(%{group_sizing: "group_count", group_count: n}) when is_integer(n),
    do: {:group_count, n}

  defp sizing(%{max_group_size: max}), do: {:max_size, max}

  defp open?(%{room: %{run: %{stopped_at: nil}}}), do: true
  defp open?(_assigns), do: false

  ## Live updates

  @impl true
  def handle_info(%{event: "presence_diff"}, socket), do: {:noreply, load(socket)}
  def handle_info({:breakout, :message, _, _, _}, socket), do: {:noreply, socket}
  def handle_info({:breakout, _, _} = _msg, socket), do: {:noreply, load(socket)}
  def handle_info({:breakout, _, _, _} = _msg, socket), do: {:noreply, load(socket)}
  def handle_info(_msg, socket), do: {:noreply, socket}

  ## Controls

  @impl true
  def handle_event("start", _params, socket) do
    case Live.start(socket.assigns.breakout, connected_people(socket.assigns.event)) do
      {:ok, _run} ->
        {:noreply, socket |> assign(:notice, nil) |> load()}

      {:error, :nobody_connected} ->
        {:noreply,
         assign(
           socket,
           :notice,
           gettext("Nobody is connected yet. People join from the event code on their phones.")
         )}

      {:error, :already_running} ->
        {:noreply, load(socket)}

      {:error, _} ->
        {:noreply, assign(socket, :notice, gettext("Could not start the breakout"))}
    end
  end

  def handle_event("add_time", %{"minutes" => minutes}, %{assigns: %{room: %{run: run}}} = socket) do
    _ = Live.add_time(run, String.to_integer(minutes))
    {:noreply, load(socket)}
  end

  def handle_event("show_group", %{"id" => id}, %{assigns: %{room: %{run: run}}} = socket) do
    group_id = if id == "", do: nil, else: String.to_integer(id)
    _ = Live.show_group(run, group_id)
    {:noreply, load(socket)}
  end

  def handle_event("send_message", %{"message" => %{"text" => text, "group" => group}}, socket) do
    %{room: %{run: run}} = socket.assigns
    group_id = if group in ["", nil], do: nil, else: String.to_integer(group)

    case Live.message(run, group_id, text) do
      :ok ->
        {:noreply,
         socket
         |> assign(:message_form, to_form(%{"text" => "", "group" => group}, as: :message))
         |> put_flash(:info, gettext("Message sent"))}

      {:error, :empty} ->
        {:noreply, socket}
    end
  end

  def handle_event("stop", _params, %{assigns: %{room: %{run: run}}} = socket) do
    _ = Live.stop(run)
    {:noreply, load(socket)}
  end

  def handle_event(_event, _params, socket), do: {:noreply, socket}

  ## Display helpers

  def preview_text(0, _sizes), do: gettext("Nobody is connected yet.")

  def preview_text(connected, sizes) do
    gettext("%{people} connected → %{groups}: %{sizes}",
      people: ngettext("1 person", "%{count} people", connected),
      groups: ngettext("1 group", "%{count} groups", length(sizes)),
      sizes: Enum.join(sizes, ", ")
    )
  end

  @impl true
  def render(assigns) do
    assigns = assign(assigns, :open, open?(assigns))

    ~H"""
    <ClaperWeb.AppHeader.header user={@current_user} title={gettext("Breakout")} />

    <div class="w-full px-4 pb-24 lg:px-6 xl:px-12">
      <div class="flex flex-wrap items-center justify-between gap-3 py-4">
        <ClaperWeb.Breadcrumbs.trail items={[
          {@event.name, ~p"/e/#{@event.code}/manage"},
          {@breakout.title, ~p"/e/#{@event.code}/breakouts/#{@breakout.id}"},
          {gettext("Live"), nil}
        ]} />
        <span :if={@open} class="badge badge-success">{gettext("Running")}</span>
      </div>

      <%!-- ===== Not running: preview and Start ===== --%>
      <section :if={!@open} class="panel mb-6">
        <div class="panel-header gap-3">
          <ClaperWeb.BreakoutLive.Icons.breakout class="size-5 text-muted" />
          <h2 class="text-base font-semibold">{@breakout.title}</h2>
        </div>
        <div class="flex flex-col gap-4 p-3">
          <p class="text-lg text-base-content">{preview_text(@connected, @preview)}</p>
          <p class="text-sm text-muted">
            {gettext(
              "Starting sorts the phones connected now into groups and gives each group its case. The groups are then locked: anyone who joins later is asked to see you for a group. Phones switch to their group's screen; the big screen shows the timer."
            )}
          </p>
          <p :if={@notice} role="alert" class="text-sm text-warning">{@notice}</p>
          <div class="flex flex-wrap gap-3">
            <button
              type="button"
              class="btn btn-primary btn-lg"
              phx-click="start"
              disabled={@connected == 0}
            >
              {if @room, do: gettext("Start again"), else: gettext("Start breakout")}
            </button>
            <.link
              navigate={~p"/e/#{@event.code}/breakouts/#{@breakout.id}"}
              class="btn btn-outline btn-lg"
            >
              {gettext("Edit breakout")}
            </.link>
          </div>
        </div>
      </section>

      <%!-- ===== Running: timer, messages, reporting back, stop ===== --%>
      <section :if={@open} class="panel mb-6">
        <div class="grid gap-4 p-3 lg:grid-cols-[auto_1fr_auto] lg:items-center">
          <div class="flex flex-wrap items-center gap-3">
            <ClaperWeb.BreakoutLive.Components.countdown
              id="bk-control-timer"
              ends_at={@room.run.ends_at}
              class="rounded-xl bg-base-300 px-4 py-2 text-2xl font-bold data-[state=up]:bg-warning data-[state=up]:text-warning-content"
            />
            <span :if={is_nil(@room.run.ends_at)} class="text-muted">{gettext("No timer")}</span>
            <div class={ClaperWeb.Component.Tabs.segmented_group_class()}>
              <button
                :for={m <- [1, 5]}
                type="button"
                phx-click="add_time"
                phx-value-minutes={m}
                class={[
                  "px-3 text-sm font-medium",
                  ClaperWeb.Component.Tabs.segmented_item_class(false)
                ]}
              >
                {gettext("+%{n} min", n: m)}
              </button>
            </div>
          </div>

          <.form
            for={@message_form}
            id="bk-message"
            phx-submit="send_message"
            class="flex flex-wrap gap-2"
          >
            <label class="sr-only" for="bk-message-group">{gettext("Send to")}</label>
            <select id="bk-message-group" name="message[group]" class="select w-auto">
              <option value="">{gettext("All groups")}</option>
              <option
                :for={g <- @room.groups}
                value={g.group.id}
                selected={to_string(g.group.id) == to_string(@message_form[:group].value)}
              >
                {gettext("Group %{n}", n: g.group.number)}
              </option>
            </select>
            <input
              type="text"
              name="message[text]"
              value={@message_form[:text].value}
              maxlength="500"
              autocomplete="off"
              placeholder={gettext("Message, e.g. 5 minutes left")}
              class="input min-w-48 flex-1"
            />
            <button type="submit" class="btn btn-outline">{gettext("Send")}</button>
          </.form>

          <button
            type="button"
            class="btn btn-error"
            phx-click="stop"
            data-confirm-title={gettext("Stop the breakout?")}
            data-confirm={gettext("Answers become final and phones go back to your slides.")}
            data-confirm-action={gettext("Stop breakout")}
            data-confirm-icon="warning"
            data-confirm-variant="destructive"
          >
            {gettext("Stop breakout")}
          </button>
        </div>

        <div :if={@room.report} class="flex flex-wrap items-center gap-3 border-t border-line p-3">
          <span class="text-base-content">
            {gettext("On the big screen and phones:")}
          </span>
          <ClaperWeb.BreakoutLive.Components.group_chip number={@room.report.result.group.number} />
          <button type="button" class="btn btn-outline btn-sm" phx-click="show_group" phx-value-id="">
            {gettext("Stop showing")}
          </button>
        </div>
      </section>

      <%!-- ===== Groups ===== --%>
      <div :if={@room} class="flex flex-col gap-3">
        <p :if={!@open} class="text-sm text-muted">
          {gettext("Last run, stopped. Its answers are final.")}
        </p>
        <div class="grid gap-4 md:grid-cols-2 xl:grid-cols-3">
          <section
            :for={g <- @room.groups}
            id={"bk-group-#{g.group.id}"}
            class="panel overflow-hidden"
          >
            <div class={[
              "-m-2 mb-0 h-1.5",
              ClaperWeb.BreakoutLive.Components.group_bar(g.group.number)
            ]}>
            </div>
            <div class="flex flex-col gap-3 p-3">
              <ClaperWeb.BreakoutLive.Components.group_heading number={g.group.number}>
                {ngettext("1 person", "%{count} people", g.size)}
              </ClaperWeb.BreakoutLive.Components.group_heading>

              <p
                :if={g.needs_note_taker?}
                class={[
                  "text-sm",
                  g.group.note_taker_identifier && "text-muted",
                  !g.group.note_taker_identifier && "text-warning"
                ]}
              >
                {if g.group.note_taker_identifier,
                  do: gettext("Has a note-taker"),
                  else: gettext("No note-taker yet")}
              </p>

              <ul :if={g.progress != []} class="flex flex-col gap-1">
                <li :for={p <- g.progress} class="flex items-center justify-between gap-3 text-sm">
                  <span class="truncate text-base-content">
                    {(@room.contents[p.piece.id] && @room.contents[p.piece.id].title) || ""}
                  </span>
                  <span class="shrink-0 tabular-nums text-muted">
                    {if p.piece.answer_scope == "group",
                      do: if(p.given > 0, do: gettext("answered"), else: gettext("waiting")),
                      else: "#{p.given}/#{p.expected}"}
                  </span>
                </li>
              </ul>

              <details class="group">
                <summary class="cursor-pointer text-sm font-medium text-base-content">
                  {gettext("Answers")}
                </summary>
                <div class="mt-3">
                  <ClaperWeb.BreakoutLive.Components.group_report
                    result={g.result}
                    contents={@room.contents}
                  />
                </div>
              </details>

              <button
                :if={@open and (is_nil(@room.report) or @room.report.result.group.id != g.group.id)}
                type="button"
                class="btn btn-outline btn-sm self-start"
                phx-click="show_group"
                phx-value-id={g.group.id}
              >
                {gettext("Show on big screen")}
              </button>
            </div>
          </section>
        </div>
      </div>
    </div>
    """
  end
end
