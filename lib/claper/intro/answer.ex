defmodule Claper.Intro.Answer do
  @moduledoc """
  A participant's answer to an interaction on the intro page (docs/INTRO.md,
  decision 12): one per phone (attendee ticket) per block, changeable until
  the event starts. `response` is checked by the interaction's piece type.
  """
  use Ecto.Schema

  @type t :: %__MODULE__{}

  schema "intro_answers" do
    field :attendee_identifier, :string
    field :response, :map, default: %{}

    belongs_to :intro_block, Claper.Intro.Block

    timestamps()
  end
end
