defmodule ClaperWeb.BreakoutLive.ViewData do
  @moduledoc """
  Builds what each Breakout screen shows from the database, so every
  LiveView reloads exactly its own viewer's slice after a change:

    * `phone/2` — one person's view: their group, packet, where they are in
      it (one task at a time), answers, and group-mates' answers where a
      piece shares them
    * `room/1` — the presenter's view: every group, its people, note-taker,
      progress and results
  """
  import Ecto.Query
  alias Claper.Repo
  alias Claper.Breakouts
  alias Claper.Breakouts.{Member, Piece, PieceType, Run}

  @doc "Content for each piece id."
  def contents(pieces), do: Map.new(pieces, &{&1.id, Breakouts.load_content(&1)})

  defp pieces(packet_id) do
    from(p in Piece, where: p.packet_id == ^packet_id, order_by: [asc: p.position, asc: p.id])
    |> Repo.all()
  end

  @doc """
  One person's view of an open run. `member` must belong to `run`.
  """
  def phone(%Run{} = run, %Member{} = member) do
    run = Breakouts.get_run!(run.id)
    group = Enum.find(run.groups, &(&1.id == member.group_id))
    pieces = if group.packet_id, do: pieces(group.packet_id), else: []
    answers = Breakouts.visible_answers(run, member)
    me = member.attendee_identifier

    own =
      answers
      |> Enum.filter(&(&1.scope == "individual" and &1.attendee_identifier == me))
      |> Map.new(&{&1.piece_id, &1.response})

    group_answers =
      answers |> Enum.filter(&(&1.scope == "group")) |> Map.new(&{&1.piece_id, &1.response})

    mates =
      answers
      |> Enum.filter(&(&1.scope == "individual" and &1.attendee_identifier != me))
      |> Enum.group_by(& &1.piece_id, & &1.response)

    %{
      run: run,
      breakout: run.breakout,
      member: member,
      group: group,
      size: length(group.members),
      pieces: pieces,
      step: min(member.step, length(pieces)),
      total: length(pieces),
      contents: contents(pieces),
      own: own,
      group_answers: group_answers,
      mates: mates,
      note_taker?: group.note_taker_identifier == me,
      has_note_taker?: not is_nil(group.note_taker_identifier),
      report: report(run)
    }
  end

  @doc """
  A group needs a note-taker only when its packet has a group answer: a
  piece the group answers once (the "Group answer" box in its editor).
  """
  def needs_note_taker?(pieces), do: Enum.any?(pieces, &(&1.answer_scope == "group"))

  @doc "The group being reported back (on the big screen and phones), or nil."
  def report(%Run{showing_group_id: nil}), do: nil

  def report(%Run{showing_group_id: id} = run) do
    case Enum.find(Breakouts.results(run), &(&1.group.id == id)) do
      nil ->
        nil

      result ->
        %{
          result: result,
          contents: contents(Enum.map(result.pieces, & &1.piece))
        }
    end
  end

  @doc """
  The presenter's view of a run: per group, its people, note-taker (when
  its tasks need one), progress per answerable piece, results.
  """
  def room(%Run{} = run) do
    run = Breakouts.get_run!(run.id)
    breakout = run.breakout
    results = Breakouts.results(run)
    answers = Breakouts.run_answers(run)
    all_pieces = Enum.flat_map(results, fn r -> Enum.map(r.pieces, & &1.piece) end)
    contents = contents(Enum.uniq_by(all_pieces, & &1.id))

    groups =
      for %{group: group, pieces: pieces} = result <- results do
        members = Enum.find(run.groups, &(&1.id == group.id)).members
        size = length(members)

        progress =
          for %{piece: piece} <- pieces, PieceType.module_for!(piece).answerable?() do
            given =
              Enum.count(answers, fn a ->
                a.group_id == group.id and a.piece_id == piece.id and
                  a.scope == piece.answer_scope
              end)

            %{
              piece: piece,
              given: given,
              expected: if(piece.answer_scope == "group", do: 1, else: size)
            }
          end

        %{
          group: group,
          result: result,
          size: size,
          needs_note_taker?: needs_note_taker?(Enum.map(pieces, & &1.piece)),
          progress: progress
        }
      end

    %{run: run, breakout: breakout, groups: groups, contents: contents, report: report(run)}
  end
end
