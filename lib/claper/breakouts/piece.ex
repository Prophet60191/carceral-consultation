defmodule Claper.Breakouts.Piece do
  @moduledoc """
  One piece of a packet: typed text (`body`), or one of the app's
  interactions, whose content stays in that interaction's own table and
  points back here through `breakout_piece_id`.

  `kind` names the piece type; `Claper.Breakouts.PieceType` lists the types
  and the contract each one meets. Answer settings:

    * `answer_scope` — "individual" (each person answers) or "group" (the
      group's note-taker answers for the group)
    * `visible_to_group` — for individual answers, whether group-mates see
      each other's answers
  """
  use Ecto.Schema

  @type t :: %__MODULE__{}
  import Ecto.Changeset

  @scopes ~w(individual group)

  schema "breakout_pieces" do
    field :position, :integer, default: 0
    field :kind, :string
    field :body, :string
    field :answer_scope, :string, default: "individual"
    field :visible_to_group, :boolean, default: false

    belongs_to :packet, Claper.Breakouts.Packet

    timestamps()
  end

  def changeset(piece, attrs) do
    piece
    |> cast(attrs, [:position, :kind, :body, :answer_scope, :visible_to_group])
    |> validate_required([:kind, :answer_scope])
    |> validate_inclusion(:kind, Claper.Breakouts.PieceType.kinds())
    |> validate_inclusion(:answer_scope, @scopes)
    |> validate_length(:body, max: 20_000)
    |> check_constraint(:answer_scope, name: :breakout_pieces_answer_scope)
    |> Claper.Breakouts.PieceType.validate_piece()
  end
end
