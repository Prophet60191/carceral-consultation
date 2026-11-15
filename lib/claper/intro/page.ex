defmodule Claper.Intro.Page do
  @moduledoc """
  An intro page (docs/INTRO.md): one per event (`event_id`), or in its
  owner's library (`event_id` nil, named by `title`).
  """
  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{}

  schema "intro_pages" do
    field :title, :string
    # An optional cover image across the top of the ticket card
    field :banner_src, :string
    field :banner_alt, :string
    # The brand at the top of the page (Jose, 2026-11-15); off hides it
    field :show_brand, :boolean, default: true

    belongs_to :user, Claper.Accounts.User
    belongs_to :event, Claper.Events.Event
    belongs_to :source_intro_page, __MODULE__

    has_many :blocks, Claper.Intro.Block,
      foreign_key: :intro_page_id,
      preload_order: [asc: :position, asc: :id]

    timestamps()
  end

  @doc """
  The banner: an image uploaded to this app (`/uploads/intro/...`) and its
  description; `banner_src` nil removes it.
  """
  def banner_changeset(page, attrs) do
    page
    |> cast(attrs, [:banner_src, :banner_alt])
    |> update_change(:banner_alt, &(&1 && String.trim(&1)))
    |> validate_length(:banner_alt, max: 200, count: :codepoints)
    |> validate_format(:banner_src, ~r{\A/uploads/intro/[a-f0-9-]+\.(png|jpg|jpeg|webp|gif)\z},
      message: "is not an uploaded image"
    )
  end

  @doc "A library page needs a name; an event's page takes the event's."
  def changeset(page, attrs) do
    page
    |> cast(attrs, [:title])
    |> update_change(:title, &(&1 && String.trim(&1)))
    |> validate_length(:title, max: 255, count: :codepoints)
    |> then(fn cs ->
      if is_nil(get_field(cs, :event_id)), do: validate_required(cs, [:title]), else: cs
    end)
  end
end
