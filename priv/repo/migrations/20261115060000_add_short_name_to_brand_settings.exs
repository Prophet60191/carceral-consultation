defmodule Claper.Repo.Migrations.AddShortNameToBrandSettings do
  use Ecto.Migration

  # The name under the app's icon on a phone's home screen (2026-11-15).
  def change do
    alter table(:brand_settings) do
      add :short_name, :string
    end
  end
end
