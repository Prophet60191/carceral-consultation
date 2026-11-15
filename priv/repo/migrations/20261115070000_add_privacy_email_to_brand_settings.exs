defmodule Claper.Repo.Migrations.AddPrivacyEmailToBrandSettings do
  use Ecto.Migration

  # Where people send privacy questions and deletion requests; shown on the
  # privacy page (2026-11-15).
  def change do
    alter table(:brand_settings) do
      add :privacy_email, :string
    end
  end
end
