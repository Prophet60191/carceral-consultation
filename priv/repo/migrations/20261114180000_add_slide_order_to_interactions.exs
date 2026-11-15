defmodule Claper.Repo.Migrations.AddSlideOrderToInteractions do
  @moduledoc """
  The presenter's order for the interactions on one slide (Reorder, in the
  manage screen's Interactions menu; Jose, 2026-11-14). Null means "not
  ordered yet": those come after the ordered ones, oldest first, as before.
  """
  use Ecto.Migration

  @tables [:polls, :forms, :embeds, :quizzes, :word_clouds, :breakouts]

  def change do
    for table <- @tables do
      alter table(table) do
        add :slide_order, :integer
      end
    end
  end
end
