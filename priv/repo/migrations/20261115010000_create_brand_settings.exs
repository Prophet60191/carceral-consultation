defmodule Claper.Repo.Migrations.CreateBrandSettings do
  @moduledoc """
  The organization's brand, set on the Brand page in Admin (2026-11-14):
  its name, short mark, description, images and source code link. One row;
  until it exists the app shows neutral defaults (Claper.Branding).
  """
  use Ecto.Migration

  def change do
    create table(:brand_settings) do
      add :name, :string
      add :monogram, :string
      add :description, :text
      add :logo_src, :string
      add :mark_src, :string
      add :icon_src, :string
      add :photo_src, :string
      add :photo_position, :string, null: false, default: "center"
      add :source_url, :string

      timestamps()
    end
  end
end
