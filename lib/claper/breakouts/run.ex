defmodule Claper.Breakouts.Run do
  @moduledoc """
  One time a breakout was run: its groups and members, the timer, and when
  it stopped (answers are final from then on). Only one run of a breakout can
  be open at a time.
  """
  use Ecto.Schema

  @type t :: %__MODULE__{}

  schema "breakout_runs" do
    field :started_at, :utc_datetime
    field :ends_at, :utc_datetime
    field :stopped_at, :utc_datetime
    field :showing_group_id, :integer

    belongs_to :breakout, Claper.Breakouts.Breakout
    has_many :groups, Claper.Breakouts.Group, preload_order: [asc: :number]
    has_many :members, Claper.Breakouts.Member

    timestamps()
  end

  def open?(%__MODULE__{stopped_at: nil}), do: true
  def open?(%__MODULE__{}), do: false
end
