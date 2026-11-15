defmodule Claper.Repo.Migrations.AddResultsOnScreenToInteractions do
  @moduledoc """
  "Show the results on the big screen", decided per interaction in its editor
  (Jose, 2026-11-14). Turning the interaction on starts the big screen from
  it; the manage screen's switch can still change it for that run. Off for
  every existing interaction, as the big screen showed nothing until
  switched on.
  """
  use Ecto.Migration

  def change do
    for table <- [:polls, :quizzes, :word_clouds, :forms] do
      alter table(table) do
        add :results_on_screen, :boolean, null: false, default: false
      end
    end
  end
end
