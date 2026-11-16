defmodule Claper.Materials.Material do
  @moduledoc """
  A PDF that belongs to an event (docs/MATERIALS.md): a **handout**, opened
  during the event, or a **take-home** file, on the page people get after
  it. The file itself is in storage (`Claper.Materials.file_path/1`); this
  is its title, switch and place in its list.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @kinds ~w(handout take_home)

  schema "materials" do
    field :uuid, Ecto.UUID, autogenerate: true
    field :kind, :string
    field :title, :string
    field :original_name, :string
    field :byte_size, :integer
    field :enabled, :boolean, default: true
    field :position, :integer, default: 0
    field :downloads, :integer, default: 0

    belongs_to :event, Claper.Events.Event

    timestamps()
  end

  def kinds, do: @kinds

  @doc "A new material: its kind, title and file details."
  def create_changeset(material, attrs) do
    material
    |> cast(attrs, [:kind, :title, :original_name, :byte_size, :enabled, :position])
    |> validate_required([:kind, :title, :byte_size])
    |> validate_inclusion(:kind, @kinds)
    |> validate_title()
  end

  @doc "What can change later: the title, the switch and the order."
  def changeset(material, attrs) do
    material
    |> cast(attrs, [:title, :enabled, :position])
    |> validate_required([:title])
    |> validate_title()
  end

  defp validate_title(changeset) do
    changeset
    |> update_change(:title, &String.trim/1)
    |> validate_required([:title])
    |> validate_length(:title, max: 120, count: :codepoints)
  end
end
