defmodule Claper.Breakouts.Packet do
  @moduledoc """
  What one group works through: an ordered stack of pieces. A breakout with
  the same material for everyone has one packet; with different material it
  has one per case, shared out across the groups in turn.
  """
  use Ecto.Schema

  @type t :: %__MODULE__{}
  import Ecto.Changeset

  schema "breakout_packets" do
    field :position, :integer, default: 0
    field :label, :string

    belongs_to :breakout, Claper.Breakouts.Breakout
    has_many :pieces, Claper.Breakouts.Piece, preload_order: [asc: :position, asc: :id]

    timestamps()
  end

  def changeset(packet, attrs) do
    packet
    |> cast(attrs, [:position, :label])
    |> validate_length(:label, max: 255, count: :codepoints)
  end
end
