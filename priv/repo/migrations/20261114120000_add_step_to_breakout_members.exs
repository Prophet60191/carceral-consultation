defmodule Claper.Repo.Migrations.AddStepToBreakoutMembers do
  @moduledoc """
  One task at a time (docs/BREAKOUT.md, decision 23): each person's place in
  their group's tasks. 0 is the first task; the number of tasks means they
  have finished them all.
  """
  use Ecto.Migration

  def change do
    alter table(:breakout_members) do
      add :step, :integer, null: false, default: 0
    end

    create constraint(:breakout_members, :breakout_members_step, check: "step >= 0")
  end
end
