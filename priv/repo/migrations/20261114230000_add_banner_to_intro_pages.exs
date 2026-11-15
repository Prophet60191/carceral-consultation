defmodule Claper.Repo.Migrations.AddBannerToIntroPages do
  @moduledoc """
  An optional banner (cover image) across the top of the intro page's ticket
  card (Jose, 2026-11-14): an uploaded image and its description.
  """
  use Ecto.Migration

  def change do
    alter table(:intro_pages) do
      add :banner_src, :string
      add :banner_alt, :string
    end
  end
end
