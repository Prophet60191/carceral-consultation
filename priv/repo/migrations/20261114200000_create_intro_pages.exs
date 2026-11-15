defmodule Claper.Repo.Migrations.CreateIntroPages do
  @moduledoc """
  Intro pages (docs/INTRO.md): the page participants see until the presenter
  starts the event, built from blocks. One per event (required), or in a
  user's library (event_id null). Existing events get a starter page.
  """
  use Ecto.Migration

  @kinds ~w(heading text image stat agenda link divider)

  def up do
    create table(:intro_pages) do
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :event_id, references(:events, on_delete: :delete_all)
      add :title, :string
      add :source_intro_page_id, references(:intro_pages, on_delete: :nilify_all)
      timestamps()
    end

    create unique_index(:intro_pages, [:event_id], where: "event_id IS NOT NULL")
    create index(:intro_pages, [:user_id], where: "event_id IS NULL")

    create table(:intro_blocks) do
      add :intro_page_id, references(:intro_pages, on_delete: :delete_all), null: false
      add :position, :integer, null: false, default: 0
      add :kind, :string, null: false
      add :data, :map, null: false, default: %{}
      timestamps()
    end

    create index(:intro_blocks, [:intro_page_id, :position])

    create constraint(:intro_blocks, :intro_blocks_kind,
             check: "kind IN (#{Enum.map_join(@kinds, ", ", &"'#{&1}'")})"
           )

    # Every existing event gets the starter page new events get.
    execute("""
    INSERT INTO intro_pages (user_id, event_id, inserted_at, updated_at)
    SELECT e.user_id, e.id, now(), now() FROM events e
    WHERE NOT EXISTS (SELECT 1 FROM intro_pages p WHERE p.event_id = e.id)
    """)

    execute("""
    INSERT INTO intro_blocks (intro_page_id, position, kind, data, inserted_at, updated_at)
    SELECT p.id, 0, 'heading', '{"text": "Welcome"}'::jsonb, now(), now()
    FROM intro_pages p WHERE p.event_id IS NOT NULL
    """)

    execute("""
    INSERT INTO intro_blocks (intro_page_id, position, kind, data, inserted_at, updated_at)
    SELECT p.id, 1, 'text', '{"body": "We will begin shortly."}'::jsonb, now(), now()
    FROM intro_pages p WHERE p.event_id IS NOT NULL
    """)
  end

  def down do
    drop table(:intro_blocks)
    drop table(:intro_pages)
  end
end
