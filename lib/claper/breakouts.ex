defmodule Claper.Breakouts do
  @moduledoc """
  Breakout groups (docs/BREAKOUT.md): building breakouts and their packets of
  pieces, the library, copying, running them (groups, late arrivals,
  note-takers, the timer, reporting back) and the answers given.

  Piece types are reached only through `Claper.Breakouts.PieceType`, so any
  interaction meeting that contract works here without changes to this
  module.

  Identity is the attendee ticket (`attendee_identifier`) every phone gets
  (see `ClaperWeb.EventController.attendee_identifier/2`).
  """
  import Ecto.Query
  alias Ecto.Multi
  alias Claper.Repo
  alias Claper.Breakouts.{Answer, Breakout, Group, Member, Packet, Piece, PieceType, Run, Sorter}

  ## Breakouts

  @doc "A breakout with its packets and pieces in order."
  def get_breakout!(id, preload \\ [packets: :pieces]),
    do: Breakout |> Repo.get!(id) |> Repo.preload(preload)

  @doc "A breakout of an event, or nil when it belongs to another event (no cross-event access)."
  def get_breakout_for_presentation(id, presentation_file_id) do
    from(b in Breakout, where: b.id == ^id and b.presentation_file_id == ^presentation_file_id)
    |> Repo.one()
    |> case do
      nil -> nil
      breakout -> Repo.preload(breakout, packets: :pieces)
    end
  end

  @doc "A library breakout of its owner, or nil."
  def get_library_breakout(id, user_id) do
    from(b in Breakout,
      where: b.id == ^id and b.user_id == ^user_id and is_nil(b.presentation_file_id)
    )
    |> Repo.one()
    |> case do
      nil -> nil
      breakout -> Repo.preload(breakout, packets: :pieces)
    end
  end

  def list_breakouts(presentation_file_id) do
    from(b in Breakout,
      where: b.presentation_file_id == ^presentation_file_id,
      order_by: [asc: b.position, asc: b.id]
    )
    |> Repo.all()
  end

  @doc "Breakouts on a slide, with `running` set when one of them is under way."
  def list_breakouts_at_position(presentation_file_id, position) do
    from(b in Breakout,
      as: :breakout,
      where: b.presentation_file_id == ^presentation_file_id and b.position == ^position,
      order_by: [asc: b.id],
      select_merge: %{
        running:
          exists(
            from r in Run,
              where: r.breakout_id == parent_as(:breakout).id and is_nil(r.stopped_at)
          )
      }
    )
    |> Repo.all()
  end

  @doc "The breakout under way in an event (by its presentation), with its run, or nil."
  def open_run_for_presentation(presentation_file_id) do
    from(r in Run,
      join: b in Breakout,
      on: b.id == r.breakout_id,
      where: b.presentation_file_id == ^presentation_file_id and is_nil(r.stopped_at),
      order_by: [desc: r.id],
      limit: 1
    )
    |> Repo.one()
    |> preload_run()
  end

  @doc "A breakout's most recent run (open or stopped), or nil."
  def latest_run(%Breakout{id: id}) do
    from(r in Run, where: r.breakout_id == ^id, order_by: [desc: r.id], limit: 1)
    |> Repo.one()
    |> preload_run()
  end

  @doc "The uuid of the event a breakout belongs to (nil in the library)."
  def event_uuid(%Breakout{presentation_file_id: nil}), do: nil

  def event_uuid(%Breakout{presentation_file_id: pf_id}) do
    from(e in Claper.Events.Event,
      join: pf in Claper.Presentations.PresentationFile,
      on: pf.event_id == e.id,
      where: pf.id == ^pf_id,
      select: e.uuid
    )
    |> Repo.one()
  end

  @doc "The owner's library, newest first."
  def list_library(user_id) do
    from(b in Breakout,
      where: b.user_id == ^user_id and is_nil(b.presentation_file_id),
      order_by: [desc: b.updated_at, desc: b.id]
    )
    |> Repo.all()
  end

  def change_breakout(%Breakout{} = breakout, attrs \\ %{}),
    do: Breakout.changeset(breakout, attrs)

  @doc """
  Creates a breakout with its first packet. `placement` holds `user_id` and,
  in an event, `presentation_file_id` and `position`.
  """
  def create_breakout(attrs, placement) do
    Multi.new()
    |> Multi.insert(:breakout, Breakout.create_changeset(%Breakout{}, attrs, placement))
    |> Multi.insert(:packet, fn %{breakout: b} -> packet_changeset(b, %{position: 0}) end)
    |> Repo.transaction()
    |> case do
      {:ok, %{breakout: breakout}} -> {:ok, get_breakout!(breakout.id)}
      {:error, _step, changeset, _} -> {:error, changeset}
    end
  end

  @doc """
  Updates a breakout's settings. Switching to the same material for everyone
  keeps only the first packet, so it is refused while there are others (the
  presenter removes them first and nothing is lost by accident).
  """
  def update_breakout(%Breakout{} = breakout, attrs) do
    changeset = Breakout.changeset(breakout, attrs)

    if Ecto.Changeset.get_field(changeset, :material_mode) == "same" and
         packet_count(breakout) > 1 do
      {:error,
       Ecto.Changeset.add_error(
         changeset,
         :material_mode,
         "Remove the other cases first; the same material for everyone uses one packet"
       )}
    else
      Repo.update(changeset)
    end
  end

  def set_placement(%Breakout{} = breakout, attrs),
    do: breakout |> Breakout.placement_changeset(attrs) |> Repo.update()

  def delete_breakout(%Breakout{} = breakout), do: Repo.delete(breakout)

  defp packet_count(breakout),
    do: Repo.aggregate(from(p in Packet, where: p.breakout_id == ^breakout.id), :count)

  ## Packets

  @doc "Every run of a breakout, newest first."
  def list_runs(%Breakout{id: id}) do
    from(r in Run, where: r.breakout_id == ^id, order_by: [desc: r.id])
    |> Repo.all()
    |> Enum.map(&preload_run/1)
  end

  defp packet_changeset(breakout, attrs),
    do: %Packet{breakout_id: breakout.id} |> Packet.changeset(attrs)

  @doc "Adds a case (packet). Only breakouts with different material per group have several."
  def add_packet(%Breakout{material_mode: "per_case"} = breakout, attrs) do
    position =
      Repo.one(from p in Packet, where: p.breakout_id == ^breakout.id, select: count(p.id))

    breakout |> packet_changeset(Map.put_new(attrs, :position, position)) |> Repo.insert()
  end

  def add_packet(%Breakout{}, _attrs),
    do: {:error, :same_material}

  def update_packet(%Packet{} = packet, attrs),
    do: packet |> Packet.changeset(attrs) |> Repo.update()

  @doc "Removes a case; a breakout always keeps at least one."
  def delete_packet(%Packet{} = packet) do
    if Repo.aggregate(from(p in Packet, where: p.breakout_id == ^packet.breakout_id), :count) > 1,
      do: Repo.delete(packet),
      else: {:error, :last_packet}
  end

  ## Pieces

  @doc """
  Adds a piece to a packet: the piece's own settings (`kind`, `body`,
  `answer_scope`, `visible_to_group`) and, for interaction pieces, the
  interaction's content (`content_attrs`), in one transaction.
  """
  def add_piece(%Packet{} = packet, piece_attrs, content_attrs \\ %{}) do
    position = Repo.one(from p in Piece, where: p.packet_id == ^packet.id, select: count(p.id))

    Multi.new()
    |> Multi.insert(
      :piece,
      %Piece{packet_id: packet.id}
      |> Piece.changeset(Map.put_new(piece_attrs, :position, position))
    )
    |> Multi.run(:content, fn _repo, %{piece: piece} ->
      PieceType.module_for!(piece).create_content(piece, content_attrs)
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{piece: piece}} -> {:ok, piece}
      {:error, _step, changeset, _} -> {:error, changeset}
    end
  end

  def update_piece(%Piece{} = piece, attrs), do: piece |> Piece.changeset(attrs) |> Repo.update()

  @doc """
  Changes a piece's own settings (`piece_attrs`, e.g. `answer_scope`) and
  its content together, in one transaction: the editor saves both at once.
  """
  def update_piece_and_content(%Piece{} = piece, piece_attrs, content_attrs) do
    Repo.transaction(fn ->
      with {:ok, piece} <- update_piece(piece, piece_attrs),
           {:ok, _content} <- update_content(piece, content_attrs) do
        piece
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  @doc "Changes a piece's content (the interaction's, or the text of a text piece)."
  def update_content(%Piece{} = piece, attrs) do
    module = PieceType.module_for!(piece)

    case module.load(piece) do
      nil -> {:error, :no_content}
      content -> module.update_content(content, attrs)
    end
  end

  @doc """
  Moves a piece one place up or down in its packet. Positions are rewritten
  0, 1, 2… in one transaction, so gaps or ties left by deletions never stick.
  """
  def move_piece(%Piece{} = piece, direction) when direction in [:up, :down] do
    pieces =
      from(p in Piece,
        where: p.packet_id == ^piece.packet_id,
        order_by: [asc: p.position, asc: p.id]
      )
      |> Repo.all()

    index = Enum.find_index(pieces, &(&1.id == piece.id))
    target = if direction == :up, do: index - 1, else: index + 1

    if index && target >= 0 && target < length(pieces) do
      reordered =
        pieces
        |> List.replace_at(index, Enum.at(pieces, target))
        |> List.replace_at(target, Enum.at(pieces, index))

      Repo.transaction(fn ->
        reordered
        |> Enum.with_index()
        |> Enum.each(fn {p, i} ->
          from(x in Piece, where: x.id == ^p.id) |> Repo.update_all(set: [position: i])
        end)
      end)
    else
      {:ok, :unchanged}
    end
  end

  @doc "A piece of a breakout, or nil when it belongs to another breakout."
  def get_piece_for_breakout(piece_id, %Breakout{id: breakout_id}) do
    from(p in Piece,
      join: k in Packet,
      on: k.id == p.packet_id,
      where: p.id == ^piece_id and k.breakout_id == ^breakout_id
    )
    |> Repo.one()
  end

  @doc "A packet of a breakout, or nil when it belongs to another breakout."
  def get_packet_for_breakout(packet_id, %Breakout{id: breakout_id}) do
    Repo.one(from k in Packet, where: k.id == ^packet_id and k.breakout_id == ^breakout_id)
  end

  def delete_piece(%Piece{} = piece), do: Repo.delete(piece)

  @doc "A piece's content (the interaction record, or the piece for typed text)."
  def load_content(%Piece{} = piece), do: PieceType.module_for!(piece).load(piece)

  ## Copies and the library

  @doc "Saves a copy of a breakout to its owner's library."
  def save_to_library(%Breakout{} = breakout, user_id),
    do: copy_breakout(breakout, %{user_id: user_id})

  @doc "Brings a library breakout into an event at a slide."
  def copy_to_event(%Breakout{} = breakout, presentation_file_id, position, user_id) do
    copy_breakout(breakout, %{
      user_id: user_id,
      presentation_file_id: presentation_file_id,
      position: position,
      source_breakout_id: if(Breakout.library?(breakout), do: breakout.id)
    })
  end

  @doc """
  Copies a breakout: settings, packets, pieces and their content. Runs and
  answers are never copied; they belong to the audience that gave them. The
  copy is switched off.
  """
  def copy_breakout(%Breakout{} = breakout, placement) do
    breakout = Repo.preload(breakout, [packets: :pieces], force: true)

    settings =
      Map.take(breakout, [
        :title,
        :material_mode,
        :group_sizing,
        :max_group_size,
        :group_count,
        :timer_minutes
      ])

    Repo.transaction(fn ->
      copy =
        %Breakout{}
        |> Breakout.create_changeset(settings, placement)
        |> Repo.insert()
        |> ok_or_rollback()

      for packet <- breakout.packets do
        new_packet =
          copy
          |> packet_changeset(%{position: packet.position, label: packet.label})
          |> Repo.insert()
          |> ok_or_rollback()

        for piece <- packet.pieces do
          new_piece =
            %Piece{packet_id: new_packet.id}
            |> Piece.changeset(
              Map.take(piece, [:position, :kind, :body, :answer_scope, :visible_to_group])
            )
            |> Repo.insert()
            |> ok_or_rollback()

          module = PieceType.module_for!(piece)

          case module.load(piece) do
            nil -> :ok
            content -> content |> module.copy_content(new_piece) |> ok_or_rollback()
          end
        end
      end

      get_breakout!(copy.id)
    end)
  end

  defp ok_or_rollback({:ok, value}), do: value
  defp ok_or_rollback({:error, reason}), do: Repo.rollback(reason)

  ## Runs

  @doc "The open run of a breakout, if any, with its groups and members."
  def open_run(%Breakout{id: id}) do
    from(r in Run, where: r.breakout_id == ^id and is_nil(r.stopped_at))
    |> Repo.one()
    |> preload_run()
  end

  def get_run!(id), do: Run |> Repo.get!(id) |> preload_run()

  defp preload_run(nil), do: nil
  defp preload_run(run), do: Repo.preload(run, groups: [:members, :packet], breakout: [])

  @doc """
  Starts a breakout for the people connected now (their attendee tickets):
  sorts them into groups, gives each group its packet, starts the timer.
  Refused when nobody is connected or the breakout is already running.
  """
  def start_run(%Breakout{} = breakout, identifiers, shuffle \\ &Enum.shuffle/1) do
    breakout = Repo.preload(breakout, :packets, force: true)
    people = Enum.uniq(identifiers)

    cond do
      people == [] ->
        {:error, :nobody_connected}

      breakout.packets == [] ->
        {:error, :no_packets}

      true ->
        sizes = Sorter.group_sizes(length(people), sizing(breakout))
        groups = Sorter.assign(people, sizes, shuffle)
        now = DateTime.utc_now() |> DateTime.truncate(:second)

        Repo.transaction(fn ->
          run =
            %Run{
              breakout_id: breakout.id,
              started_at: now,
              ends_at: breakout.timer_minutes && DateTime.add(now, breakout.timer_minutes * 60)
            }
            |> Ecto.Changeset.change()
            |> Ecto.Changeset.unique_constraint(:breakout_id, name: :breakout_runs_one_open_index)
            |> Repo.insert()
            |> case do
              {:ok, run} -> run
              {:error, _} -> Repo.rollback(:already_running)
            end

          groups
          |> Enum.with_index()
          |> Enum.each(fn {members, index} ->
            group =
              Repo.insert!(%Group{
                run_id: run.id,
                number: index + 1,
                packet_id: Sorter.packet_for(index, breakout.packets).id
              })

            Enum.each(members, fn identifier ->
              Repo.insert!(%Member{
                run_id: run.id,
                group_id: group.id,
                attendee_identifier: identifier
              })
            end)
          end)

          get_run!(run.id)
        end)
    end
  end

  defp sizing(%Breakout{group_sizing: "group_count", group_count: count}) when is_integer(count),
    do: {:group_count, count}

  defp sizing(%Breakout{max_group_size: max}), do: {:max_size, max}

  @doc "Where a person is in a run: their membership with its group, or nil."
  def membership(%Run{id: run_id}, identifier) do
    from(m in Member,
      where: m.run_id == ^run_id and m.attendee_identifier == ^identifier,
      preload: [group: :packet]
    )
    |> Repo.one()
  end

  @doc """
  Moves a person to another task of their group, one at a time (decision
  23): `step` runs from 0 (the first task) to `task_count` (all finished).
  Steps outside that range are refused.
  """
  def set_step(%Member{} = member, step, task_count)
      when is_integer(step) and step >= 0 and step <= task_count do
    member |> Ecto.Changeset.change(step: step) |> Repo.update()
  end

  def set_step(%Member{}, _step, _task_count), do: {:error, :out_of_range}

  ## Note-takers

  @doc """
  A group member volunteers to take notes; the first to ask gets it.
  Returns `{:error, :taken}` when someone already has, `{:error,
  :not_in_group}` for people outside the group.
  """
  def claim_note_taker(%Group{id: group_id, run_id: run_id}, identifier) do
    with %Member{group_id: ^group_id} <-
           membership(%Run{id: run_id}, identifier) || :not_in_group,
         {1, _} <-
           from(g in Group, where: g.id == ^group_id and is_nil(g.note_taker_identifier))
           |> Repo.update_all(set: [note_taker_identifier: identifier, updated_at: now()]) do
      {:ok, Repo.get!(Group, group_id)}
    else
      {0, _} -> {:error, :taken}
      _ -> {:error, :not_in_group}
    end
  end

  @doc "The note-taker hands off: the group is offered the role again. Nothing written is lost."
  def hand_off_note_taker(%Group{id: group_id}, identifier) do
    from(g in Group, where: g.id == ^group_id and g.note_taker_identifier == ^identifier)
    |> Repo.update_all(set: [note_taker_identifier: nil, updated_at: now()])
    |> case do
      {1, _} -> {:ok, Repo.get!(Group, group_id)}
      {0, _} -> {:error, :not_note_taker}
    end
  end

  @doc """
  Frees the role only if `identifier` still holds it: used when a note-taker's
  phone has been gone a while, so a hand-off that already happened is never
  undone. Returns `{:ok, group}` when the role was freed, `:unchanged` otherwise.
  """
  def clear_note_taker_if(%Group{id: group_id}, identifier) do
    from(g in Group, where: g.id == ^group_id and g.note_taker_identifier == ^identifier)
    |> Repo.update_all(set: [note_taker_identifier: nil, updated_at: now()])
    |> case do
      {1, _} -> {:ok, Repo.get!(Group, group_id)}
      {0, _} -> :unchanged
    end
  end

  @doc "Frees the role when the note-taker's phone has been gone too long (server use only)."
  def clear_note_taker(%Group{id: group_id}) do
    from(g in Group, where: g.id == ^group_id)
    |> Repo.update_all(set: [note_taker_identifier: nil, updated_at: now()])

    {:ok, Repo.get!(Group, group_id)}
  end

  ## Timer, reporting back, stopping

  @doc "Adds minutes to the timer (from now, if time was already up). The timer only signals."
  def add_time(%Run{} = run, minutes) when is_integer(minutes) and minutes > 0 do
    with :ok <- ensure_open(run) do
      from_time =
        case run.ends_at do
          nil -> now()
          ends_at -> Enum.max([ends_at, now()], DateTime)
        end

      run
      |> Ecto.Changeset.change(ends_at: DateTime.add(from_time, minutes * 60))
      |> Repo.update()
    end
  end

  @doc "Puts one group's work on the big screen and the phones, or none (`nil`)."
  def show_group(%Run{} = run, group_id) do
    valid? =
      is_nil(group_id) or
        Repo.exists?(from g in Group, where: g.id == ^group_id and g.run_id == ^run.id)

    if valid?,
      do: run |> Ecto.Changeset.change(showing_group_id: group_id) |> Repo.update(),
      else: {:error, :unknown_group}
  end

  @doc "Stops the breakout: answers are final from now on."
  def stop_run(%Run{} = run) do
    with :ok <- ensure_open(run) do
      run |> Ecto.Changeset.change(stopped_at: now()) |> Repo.update()
    end
  end

  defp ensure_open(%Run{id: id}) do
    if Repo.exists?(from r in Run, where: r.id == ^id and is_nil(r.stopped_at)),
      do: :ok,
      else: {:error, :stopped}
  end

  defp now, do: DateTime.utc_now() |> DateTime.truncate(:second)

  ## Answers

  @doc """
  Saves (or replaces) an answer while the breakout runs. Each piece's setting
  decides whose answer it is: a person's own, or the group's, which only the
  group's note-taker may write. People can only answer pieces of their own
  group's packet.
  """
  def put_answer(%Run{} = run, %Piece{} = piece, identifier, params) do
    module = PieceType.module_for!(piece)

    with :ok <- ensure_open(run),
         %Member{group: group} <- membership(run, identifier) || {:error, :not_in_run},
         true <- piece.packet_id == group.packet_id || {:error, :not_your_packet},
         true <- module.answerable?() || {:error, :not_answerable},
         :ok <- may_write(piece, group, identifier),
         {:ok, response} <- module.validate_response(module.load(piece), params) do
      upsert_answer(%Answer{
        run_id: run.id,
        piece_id: piece.id,
        group_id: group.id,
        attendee_identifier: identifier,
        scope: piece.answer_scope,
        response: response
      })
    end
  end

  @doc """
  Takes an answer back while the breakout runs (someone cleared their
  choice). The same rules as `put_answer/4` decide whose answer it is and
  who may change it. Returns `{:ok, group_id}`.
  """
  def withdraw_answer(%Run{} = run, %Piece{} = piece, identifier) do
    with :ok <- ensure_open(run),
         %Member{group: group} <- membership(run, identifier) || {:error, :not_in_run},
         true <- piece.packet_id == group.packet_id || {:error, :not_your_packet},
         :ok <- may_write(piece, group, identifier) do
      query =
        case piece.answer_scope do
          "group" ->
            from(a in Answer,
              where: a.run_id == ^run.id and a.piece_id == ^piece.id and a.group_id == ^group.id,
              where: a.scope == "group"
            )

          _ ->
            from(a in Answer,
              where: a.run_id == ^run.id and a.piece_id == ^piece.id,
              where: a.attendee_identifier == ^identifier and a.scope == "individual"
            )
        end

      Repo.delete_all(query)
      {:ok, group.id}
    end
  end

  defp may_write(%Piece{answer_scope: "group"}, %Group{id: id}, identifier) do
    if Repo.exists?(
         from g in Group, where: g.id == ^id and g.note_taker_identifier == ^identifier
       ),
       do: :ok,
       else: {:error, :not_note_taker}
  end

  defp may_write(%Piece{}, _group, _identifier), do: :ok

  defp upsert_answer(%Answer{scope: "individual"} = answer) do
    Repo.insert(answer,
      on_conflict: {:replace, [:response, :updated_at]},
      conflict_target:
        {:unsafe_fragment, "(run_id, piece_id, attendee_identifier) WHERE scope = 'individual'"},
      returning: true
    )
  end

  defp upsert_answer(%Answer{scope: "group"} = answer) do
    Repo.insert(answer,
      on_conflict: {:replace, [:response, :attendee_identifier, :updated_at]},
      conflict_target: {:unsafe_fragment, "(run_id, piece_id, group_id) WHERE scope = 'group'"},
      returning: true
    )
  end

  @doc """
  The answers a group member may see: their own, their group's answers, and
  group-mates' answers on pieces set to be shared within the group.
  """
  def visible_answers(%Run{id: run_id}, %Member{} = member) do
    from(a in Answer,
      join: p in Piece,
      on: p.id == a.piece_id,
      where: a.run_id == ^run_id and a.group_id == ^member.group_id,
      where:
        a.scope == "group" or a.attendee_identifier == ^member.attendee_identifier or
          p.visible_to_group == true,
      order_by: [asc: a.inserted_at, asc: a.id]
    )
    |> Repo.all()
  end

  @doc "Every answer of a run (the presenter's view and results)."
  def run_answers(%Run{id: run_id}) do
    from(a in Answer, where: a.run_id == ^run_id, order_by: [asc: a.inserted_at, asc: a.id])
    |> Repo.all()
  end

  @doc """
  Results by group: for each group, each piece of its packet summed up by
  the piece's type from the answers that piece's setting counts (the group
  answer for group pieces, individual answers otherwise).
  """
  def results(%Run{id: id}) do
    run = get_run!(id)
    answers = run |> run_answers() |> Enum.group_by(&{&1.group_id, &1.piece_id})

    pieces_by_packet =
      from(p in Piece,
        where: p.packet_id in ^(run.groups |> Enum.map(& &1.packet_id) |> Enum.reject(&is_nil/1)),
        order_by: [asc: p.position, asc: p.id]
      )
      |> Repo.all()
      |> Enum.group_by(& &1.packet_id)

    for group <- run.groups do
      pieces =
        for piece <- Map.get(pieces_by_packet, group.packet_id, []) do
          module = PieceType.module_for!(piece)

          responses =
            answers
            |> Map.get({group.id, piece.id}, [])
            |> Enum.filter(&(&1.scope == piece.answer_scope))
            |> Enum.map(& &1.response)

          %{
            piece: piece,
            summary:
              if(module.answerable?(),
                do: module.summarize(module.load(piece), responses),
                else: %{}
              )
          }
        end

      %{group: group, pieces: pieces}
    end
  end
end
