defmodule Claper.Repo.Migrations.CreateMaterials do
  use Ecto.Migration

  # Materials (docs/MATERIALS.md, 2026-11-15): PDFs handed out during an
  # event and PDFs to take home after it, plus the event's take-home
  # settings (the slides switch, and until when the take-home page is open).
  def change do
    create table(:materials) do
      add :uuid, :binary_id, null: false
      add :event_id, references(:events, on_delete: :delete_all), null: false
      add :kind, :string, null: false
      add :title, :string, null: false
      add :original_name, :string
      add :byte_size, :integer, null: false
      add :enabled, :boolean, null: false, default: true
      add :position, :integer, null: false, default: 0
      add :downloads, :integer, null: false, default: 0

      timestamps()
    end

    create unique_index(:materials, [:uuid])
    create index(:materials, [:event_id, :kind, :position])

    alter table(:events) do
      # nil: 7 days after the event ends (Claper.Materials.take_home_until/1)
      add :take_home_until, :naive_datetime
      add :take_home_slides, :boolean, null: false, default: false
    end
  end
end
