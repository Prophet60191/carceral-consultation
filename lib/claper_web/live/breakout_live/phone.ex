defmodule ClaperWeb.BreakoutLive.Phone do
  @moduledoc """
  The breakout on the audience's phones (docs/BREAKOUT.md, step 5), run
  inside the event page (`ClaperWeb.EventLive.Show`), which hands over its
  `bk_*` events and `{:breakout, ...}` messages.

  While a breakout runs, the phone shows its group's screen instead of the
  slides: group number and color, its tasks one at a time (Back / Next,
  decision 23), the note-taker request on group answers, answering,
  messages from the presenter, and reporting back. When it stops, the
  slides come back.

  People connected when it starts were sorted into groups, and the groups
  are then locked (decision 24): anyone who opens the app later sees "See
  the presenter to be assigned to a group" until it stops. A note-taker whose phone has been
  gone for `@note_taker_grace` frees the role for the group (checked by the
  group's other phones; only the one that still holds it is freed).
  """
  import Phoenix.Component, only: [assign: 2, assign: 3]
  use Gettext, backend: ClaperWeb.Gettext

  alias Claper.Breakouts
  alias Claper.Breakouts.Live
  alias ClaperWeb.BreakoutLive.ViewData

  @note_taker_grace 60_000

  @doc "Sets up the phone's breakout state (call when the event page mounts)."
  def init(socket) do
    socket
    |> assign(:breakout_state, nil)
    |> assign(:breakout_outside, nil)
    |> assign(:breakout_message, nil)
    |> assign(:breakout_error, nil)
    |> load()
  end

  @doc """
  Reloads this phone's view of the breakout under way: its group's screen,
  or, for someone not in a group, the breakout they arrived during.
  """
  def load(%{assigns: %{event: event, attendee_identifier: me}} = socket) do
    with true <- Phoenix.LiveView.connected?(socket),
         %{} = run <- Breakouts.open_run_for_presentation(event.presentation_file.id) do
      case Breakouts.membership(run, me) do
        nil ->
          assign(socket,
            breakout_state: nil,
            breakout_message: nil,
            breakout_outside: Breakouts.get_breakout!(run.breakout_id, [])
          )

        member ->
          assign(socket,
            breakout_state: ViewData.phone(run, member),
            breakout_outside: nil
          )
      end
    else
      _ -> assign(socket, breakout_state: nil, breakout_message: nil, breakout_outside: nil)
    end
  end

  def load(socket), do: socket

  ## Messages from the event channel

  def handle_info({:breakout, :changed, _run_id}, socket), do: {:noreply, load(socket)}

  def handle_info({:breakout, kind, run_id, group_id}, socket) when kind in [:group, :answer] do
    case socket.assigns[:breakout_state] do
      %{run: %{id: ^run_id}, group: %{id: ^group_id}} ->
        {:noreply, load(socket)}

      # The group on the big screen may have changed answers.
      %{run: %{id: ^run_id}, report: %{result: %{group: %{id: ^group_id}}}} ->
        {:noreply, load(socket)}

      _ ->
        {:noreply, socket}
    end
  end

  def handle_info({:breakout, :message, run_id, group_id, text}, socket) do
    case socket.assigns[:breakout_state] do
      %{run: %{id: ^run_id}, group: group} when is_nil(group_id) or group_id == group.id ->
        {:noreply, assign(socket, :breakout_message, text)}

      _ ->
        {:noreply, socket}
    end
  end

  def handle_info({:bk_check_note_taker, group_id, identifier}, socket) do
    with %{run: run, group: %{id: ^group_id} = group} <- socket.assigns[:breakout_state],
         false <- present?(socket, identifier),
         {:ok, _} <- Live.release_absent_note_taker(run, group, identifier) do
      {:noreply, load(socket)}
    else
      _ -> {:noreply, socket}
    end
  end

  @doc """
  On presence changes: if this group's note-taker has left, check again
  after the grace period.
  """
  def presence_changed(socket) do
    case socket.assigns[:breakout_state] do
      %{group: %{id: group_id, note_taker_identifier: nt}, member: %{attendee_identifier: me}}
      when is_binary(nt) and nt != me ->
        unless present?(socket, nt),
          do: Process.send_after(self(), {:bk_check_note_taker, group_id, nt}, @note_taker_grace)

        socket

      _ ->
        socket
    end
  end

  defp present?(%{assigns: %{event: event}}, identifier) do
    ClaperWeb.Presence.list("event:#{event.uuid}") |> Map.has_key?(identifier)
  end

  ## Events from the phone

  def handle_event(_event, _params, %{assigns: %{breakout_state: nil}} = socket),
    do: {:noreply, socket}

  def handle_event("bk_dismiss_message", _params, socket),
    do: {:noreply, assign(socket, :breakout_message, nil)}

  def handle_event("bk_next", _params, %{assigns: %{breakout_state: state}} = socket),
    do: step(socket, state.step + 1)

  def handle_event("bk_back", _params, %{assigns: %{breakout_state: state}} = socket),
    do: step(socket, state.step - 1)

  def handle_event("bk_claim", _params, %{assigns: %{breakout_state: state}} = socket) do
    _ = Live.claim_note_taker(state.run, state.group, me(socket))
    {:noreply, load(socket)}
  end

  def handle_event("bk_hand_off", _params, %{assigns: %{breakout_state: state}} = socket) do
    _ = Live.hand_off_note_taker(state.run, state.group, me(socket))
    {:noreply, load(socket)}
  end

  # Answering (the response is built by BreakoutLive.Responses, shared with
  # the intro page).
  def handle_event("bk_" <> action, %{"piece" => piece_id} = params, socket)
      when action in ["poll", "quiz", "form", "word_add", "word_remove"] do
    with_piece(socket, piece_id, fn piece, content, current ->
      case ClaperWeb.BreakoutLive.Responses.build(action, params, content, current) do
        {:ok, response, opts} -> answer(socket, piece, response, opts)
        :ignore -> {:noreply, socket}
      end
    end)
  end

  def handle_event(_event, _params, socket), do: {:noreply, socket}

  defp step(%{assigns: %{breakout_state: state}} = socket, step) do
    _ = Breakouts.set_step(state.member, step, state.total)
    {:noreply, socket |> assign(:breakout_error, nil) |> load()}
  end

  # Runs `fun` with a piece of this person's packet, its content and the answer
  # currently shown for it (their own, or the group's for group pieces). Only
  # tasks they have reached can be answered: no skipping ahead.
  defp with_piece(%{assigns: %{breakout_state: state}} = socket, piece_id, fun) do
    reached = Enum.take(state.pieces, state.step + 1)

    case Enum.find(reached, &(to_string(&1.id) == to_string(piece_id))) do
      nil ->
        {:noreply, socket}

      piece ->
        current =
          if piece.answer_scope == "group",
            do: state.group_answers[piece.id],
            else: state.own[piece.id]

        fun.(piece, state.contents[piece.id], current)
    end
  end

  # A cleared answer (nothing chosen or written) is taken back rather than saved.
  defp answer(socket, piece, params, opts) do
    run = socket.assigns.breakout_state.run

    result =
      if opts[:empty?],
        do: Live.withdraw(run, piece, me(socket)),
        else: Live.answer(run, piece, me(socket), params)

    case result do
      :ok ->
        {:noreply, socket |> assign(:breakout_error, nil) |> load()}

      {:ok, _} ->
        {:noreply, socket |> assign(:breakout_error, nil) |> load()}

      {:error, reason} when is_binary(reason) ->
        if opts[:quiet],
          do: {:noreply, socket},
          else: {:noreply, assign(socket, :breakout_error, reason)}

      {:error, :not_note_taker} ->
        {:noreply,
         assign(
           socket,
           :breakout_error,
           gettext("Only your group's note-taker can answer this one")
         )}

      {:error, :stopped} ->
        {:noreply, load(socket)}

      {:error, _} ->
        {:noreply, assign(socket, :breakout_error, gettext("Could not save your answer"))}
    end
  end

  defp me(socket), do: socket.assigns.attendee_identifier
end
