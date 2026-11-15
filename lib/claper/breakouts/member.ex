defmodule Claper.Breakouts.Member do
  @moduledoc """
  A person (their attendee ticket) in a group of a run.

    * `step` — where they are in their group's tasks, one at a time
      (decision 23): 0 is the first task; the number of tasks means they
      have finished them all
    * `late` — set only by runs before 2026-11-14, when people arriving after
      the start were added to a group. Groups are now locked when the
      breakout starts (decision 24); the column keeps that history.
  """
  use Ecto.Schema

  @type t :: %__MODULE__{}

  schema "breakout_members" do
    field :attendee_identifier, :string
    field :step, :integer, default: 0
    field :late, :boolean, default: false

    belongs_to :run, Claper.Breakouts.Run
    belongs_to :group, Claper.Breakouts.Group

    timestamps()
  end
end
