defmodule Claper.Repo.Migrations.AddSlidesDownloadsToEvents do
  use Ecto.Migration

  # How many times the slides were downloaded from the take-home page
  # (docs/MATERIALS.md, step 5): a count only, never who.
  def change do
    alter table(:events) do
      add :slides_downloads, :integer, null: false, default: 0
    end
  end
end
