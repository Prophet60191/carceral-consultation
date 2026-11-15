defmodule Claper.Polls.Poll do
  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{
          id: integer(),
          title: String.t(),
          position: integer() | nil,
          total: integer() | nil,
          enabled: boolean() | nil,
          multiple: boolean() | nil,
          presentation_file_id: integer() | nil,
          poll_opts: [Claper.Polls.PollOpt.t()],
          poll_votes: [Claper.Polls.PollVote.t()] | nil,
          show_results: boolean() | nil,
          results_on_screen: boolean(),
          inserted_at: NaiveDateTime.t(),
          updated_at: NaiveDateTime.t()
        }

  @derive {Jason.Encoder, only: [:title, :position]}
  schema "polls" do
    field :title, :string
    field :position, :integer
    # Order among the interactions on its slide (Interactions.reorder/3); set by the server only
    field :slide_order, :integer
    field :total, :integer, virtual: true
    field :enabled, :boolean
    field :multiple, :boolean
    field :show_results, :boolean
    # Show the results on the big screen when turned on (decided in the editor;
    # the manage screen's switch can change it for the run). Slides only.
    field :results_on_screen, :boolean, default: false

    belongs_to :presentation_file, Claper.Presentations.PresentationFile
    belongs_to :breakout_piece, Claper.Breakouts.Piece
    belongs_to :intro_block, Claper.Intro.Block

    has_many :poll_opts, Claper.Polls.PollOpt,
      preload_order: [asc: :id],
      on_replace: :delete

    has_many :poll_votes, Claper.Polls.PollVote, on_replace: :delete

    timestamps()
  end

  @doc """
  Fields a presenter may edit through the poll form. `presentation_file_id`
  decides which event owns the poll and is only set on creation by the server.
  """
  def changeset(poll, attrs) do
    poll
    |> content_changeset(attrs)
    |> cast(attrs, [:results_on_screen])
    |> validate_required([:presentation_file_id, :position])
  end

  @doc """
  The content alone, for an interaction used as a breakout piece: it has no
  slide; `breakout_piece_id` is set by the server before this runs.
  """
  def piece_changeset(poll, attrs) do
    poll
    |> content_changeset(attrs)
    |> Claper.Breakouts.Pieces.Content.require_owner()
  end

  defp content_changeset(poll, attrs) do
    poll
    |> cast(attrs, [:title, :position, :enabled, :total, :multiple, :show_results])
    |> cast_assoc(:poll_opts, required: true)
    |> validate_required([:title])
    |> validate_length(:title, max: 255)
  end

  def create_changeset(poll, attrs) do
    poll
    |> cast(attrs, [:presentation_file_id])
    |> changeset(attrs)
  end
end
