defmodule Claper.Breakouts.Export do
  @moduledoc """
  A breakout run as rows for a CSV file (docs/BREAKOUT.md, step 6): one row
  per answer part, ordered by group, then piece, then person.

  Individual answers carry the same encoded attendee code as the app's other
  exports (so a person can be followed across files without a name); group
  answers say "Group (note-taker)". Pieces nobody answers (text, web
  content) have no rows.
  """
  import Ecto.Query
  alias Claper.Repo
  alias Claper.Breakouts
  alias Claper.Breakouts.{Piece, PieceType, Run}

  @headers [
    "Breakout",
    "Run started (UTC)",
    "Run stopped (UTC)",
    "Group",
    "Piece",
    "Piece type",
    "Piece title",
    "Answered by",
    "Part",
    "Answer",
    "Saved at (UTC)"
  ]

  def headers, do: @headers

  @doc "The rows of a run, in the order of `headers/0`."
  def rows(%Run{} = run) do
    run = Breakouts.get_run!(run.id)
    groups = Map.new(run.groups, &{&1.id, &1})

    pieces =
      from(p in Piece,
        where: p.packet_id in ^(run.groups |> Enum.map(& &1.packet_id) |> Enum.reject(&is_nil/1))
      )
      |> Repo.all()
      |> Map.new(&{&1.id, &1})

    contents = Map.new(pieces, fn {id, piece} -> {id, Breakouts.load_content(piece)} end)

    run
    |> Breakouts.run_answers()
    |> Enum.filter(&Map.has_key?(pieces, &1.piece_id))
    |> Enum.sort_by(fn a ->
      {groups[a.group_id].number, pieces[a.piece_id].position, a.scope, a.attendee_identifier}
    end)
    |> Enum.flat_map(fn answer ->
      piece = pieces[answer.piece_id]
      group = groups[answer.group_id]
      module = PieceType.module_for!(piece)
      content = contents[piece.id]

      for {part, text} <- module.describe_response(content, answer.response) do
        [
          run.breakout.title,
          run.started_at,
          run.stopped_at,
          group.number,
          piece.position + 1,
          module.label(),
          content && Map.get(content, :title),
          answered_by(answer),
          part,
          text,
          answer.updated_at
        ]
      end
    end)
  end

  defp answered_by(%{scope: "group"}), do: "Group (note-taker)"
  defp answered_by(%{attendee_identifier: id}), do: Base.encode16(id)
end
