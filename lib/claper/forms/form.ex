defmodule Claper.Forms.Form do
  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{
          id: integer(),
          enabled: boolean() | nil,
          position: integer() | nil,
          title: String.t(),
          results_on_screen: boolean(),
          fields: [Claper.Forms.Field.t()] | nil,
          presentation_file_id: integer() | nil,
          form_submits: [Claper.Forms.FormSubmit.t()] | nil,
          inserted_at: NaiveDateTime.t(),
          updated_at: NaiveDateTime.t()
        }

  @derive {Jason.Encoder, only: [:title, :position]}
  schema "forms" do
    field :enabled, :boolean, default: true
    field :position, :integer, default: 0
    # Order among the interactions on its slide (Interactions.reorder/3); set by the server only
    field :slide_order, :integer
    field :title, :string
    # Show the answers on the big screen when turned on (decided in the editor;
    # the manage screen's switch can change it for the run). Slides only.
    field :results_on_screen, :boolean, default: false
    embeds_many :fields, Claper.Forms.Field, on_replace: :delete

    belongs_to :presentation_file, Claper.Presentations.PresentationFile
    belongs_to :breakout_piece, Claper.Breakouts.Piece
    belongs_to :intro_block, Claper.Intro.Block
    has_many :form_submits, Claper.Forms.FormSubmit, on_replace: :delete

    timestamps()
  end

  @doc """
  Fields a presenter may edit through the form editor. `presentation_file_id`
  decides which event owns the form and is only set on creation by the server.
  """
  def changeset(form, attrs \\ %{}) do
    form
    |> content_changeset(attrs)
    |> cast(attrs, [:results_on_screen])
    |> validate_required([:presentation_file_id, :position])
  end

  @doc """
  The content alone, for an interaction used as a breakout piece: it has no
  slide; `breakout_piece_id` is set by the server before this runs.
  """
  def piece_changeset(form, attrs) do
    form
    |> content_changeset(attrs)
    |> Claper.Breakouts.Pieces.Content.require_owner()
  end

  defp content_changeset(form, attrs) do
    form
    |> cast(attrs, [:enabled, :title, :position])
    |> cast_embed(:fields)
    |> validate_required([:title])
  end

  def create_changeset(form, attrs) do
    form
    |> cast(attrs, [:presentation_file_id])
    |> changeset(attrs)
  end
end
