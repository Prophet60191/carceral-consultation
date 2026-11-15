defmodule Claper.Repo.Migrations.AddStartedToPresentationStates do
  @moduledoc """
  Start Event (docs/INTRO.md, decision 5): the presenter starts the event;
  until then participants see the intro page. Events whose scheduled start
  has already passed count as started, so nothing changes for them.
  """
  use Ecto.Migration

  def up do
    alter table(:presentation_states) do
      add :started, :boolean, null: false, default: false
    end

    execute("""
    UPDATE presentation_states ps SET started = true
    FROM presentation_files pf JOIN events e ON e.id = pf.event_id
    WHERE pf.id = ps.presentation_file_id AND e.started_at <= (now() at time zone 'utc')
    """)
  end

  def down do
    alter table(:presentation_states) do
      remove :started
    end
  end
end
