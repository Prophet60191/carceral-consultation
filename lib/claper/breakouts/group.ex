defmodule Claper.Breakouts.Group do
  @moduledoc "A group in a run: its number, its packet and its note-taker (if one has volunteered)."
  use Ecto.Schema

  @type t :: %__MODULE__{}

  schema "breakout_groups" do
    field :number, :integer
    field :note_taker_identifier, :string

    belongs_to :run, Claper.Breakouts.Run
    belongs_to :packet, Claper.Breakouts.Packet
    has_many :members, Claper.Breakouts.Member

    timestamps()
  end
end
