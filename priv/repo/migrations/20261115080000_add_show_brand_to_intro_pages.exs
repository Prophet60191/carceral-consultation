defmodule Claper.Repo.Migrations.AddShowBrandToIntroPages do
  use Ecto.Migration

  # Whether the brand shows at the top of the intro page (Jose, 2026-11-15).
  # Existing pages keep showing it.
  def change do
    alter table(:intro_pages) do
      add :show_brand, :boolean, null: false, default: true
    end
  end
end
