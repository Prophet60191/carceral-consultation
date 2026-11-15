defmodule Claper.Branding.Brand do
  @moduledoc """
  The organization's brand (one row, `brand_settings`). Every field may be
  empty: `Claper.Branding` fills in neutral defaults, so a fresh copy of the
  app works and looks plain until its owner sets the brand on the Brand page.

  Images (`*_src`) are only ever set by the server, to files it stored under
  `/uploads/brand/` (`Claper.Branding.put_image/3`); they are never cast from
  a form.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @photo_positions ~w(left center right)

  schema "brand_settings" do
    field :name, :string
    field :monogram, :string
    field :short_name, :string
    field :description, :string
    field :logo_src, :string
    field :mark_src, :string
    field :icon_src, :string
    field :photo_src, :string
    field :photo_position, :string, default: "center"
    field :source_url, :string
    field :privacy_email, :string

    timestamps()
  end

  def photo_positions, do: @photo_positions

  @doc "The fields the Brand page edits (text only; images have their own steps)."
  def changeset(brand, attrs) do
    brand
    |> cast(
      attrs,
      [:name, :monogram, :short_name, :description, :photo_position, :source_url, :privacy_email],
      empty_values: [nil, ""]
    )
    |> update_change(:name, &trim/1)
    |> update_change(:monogram, &trim/1)
    |> update_change(:short_name, &trim/1)
    |> update_change(:description, &trim/1)
    |> update_change(:source_url, &trim/1)
    |> update_change(:privacy_email, &trim/1)
    |> validate_length(:name, max: 80)
    |> validate_length(:monogram, max: 3)
    |> validate_length(:short_name, max: Claper.Branding.short_name_max())
    |> validate_length(:description, max: 600)
    |> validate_inclusion(:photo_position, @photo_positions)
    |> validate_source_url()
    |> validate_length(:privacy_email, max: 160)
    |> validate_format(:privacy_email, ~r/^[^\s@]+@[^\s@]+\.[^\s@]+$/,
      message: Gettext.gettext(ClaperWeb.Gettext, "Enter an email address")
    )
  end

  @doc false
  def image_changeset(brand, field, src), do: change(brand, [{field, src}])

  # Spaces around are dropped; nothing left means "use the default".
  defp trim(nil), do: nil

  defp trim(text) do
    case String.trim(text) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  # The license (AGPL-3.0, section 13) asks for a working link to this copy's
  # source code, so only a full web address is accepted.
  defp validate_source_url(changeset) do
    validate_change(changeset, :source_url, fn :source_url, url ->
      case URI.parse(url) do
        %URI{scheme: scheme, host: host}
        when scheme in ["http", "https"] and host not in [nil, ""] ->
          []

        _ ->
          [
            source_url:
              Gettext.gettext(
                ClaperWeb.Gettext,
                "Enter a full web address, starting with https://"
              )
          ]
      end
    end)
  end
end
