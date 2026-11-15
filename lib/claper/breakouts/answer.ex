defmodule Claper.Breakouts.Answer do
  @moduledoc """
  An answer to a piece in a run. Individual answers belong to one person;
  group answers belong to the group (written by its note-taker). The
  `response` shape is defined by the piece's type (`PieceType`).
  """
  use Ecto.Schema

  @type t :: %__MODULE__{}

  schema "breakout_answers" do
    field :attendee_identifier, :string
    field :scope, :string
    field :response, :map, default: %{}

    belongs_to :run, Claper.Breakouts.Run
    belongs_to :piece, Claper.Breakouts.Piece
    belongs_to :group, Claper.Breakouts.Group

    timestamps()
  end
end
