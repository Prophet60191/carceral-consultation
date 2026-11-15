defmodule Claper.Breakouts.Breakout do
  @moduledoc """
  A breakout: the room split into small groups, each working through a
  packet of pieces (docs/BREAKOUT.md).

  In an event it belongs to a slide (`presentation_file_id` + `position`),
  like every interaction. In the library it has neither and belongs only to
  its owner (`user_id`).
  """
  use Ecto.Schema

  @type t :: %__MODULE__{}
  import Ecto.Changeset

  @material_modes ~w(same per_case)
  @group_sizings ~w(max_size group_count)

  schema "breakouts" do
    field :uuid, Ecto.UUID
    field :title, :string
    field :position, :integer
    # Order among the interactions on its slide (Interactions.reorder/3); set by the server only
    field :slide_order, :integer
    field :enabled, :boolean, default: false
    field :material_mode, :string, default: "same"
    field :group_sizing, :string, default: "max_size"
    field :max_group_size, :integer, default: 5
    field :group_count, :integer
    field :timer_minutes, :integer
    field :running, :boolean, virtual: true, default: false

    belongs_to :presentation_file, Claper.Presentations.PresentationFile
    belongs_to :user, Claper.Accounts.User
    belongs_to :source_breakout, __MODULE__

    has_many :packets, Claper.Breakouts.Packet, preload_order: [asc: :position, asc: :id]
    has_many :runs, Claper.Breakouts.Run

    timestamps()
  end

  @doc "Fields the presenter edits. Ownership and placement are set by the server."
  def changeset(breakout, attrs) do
    breakout
    |> cast(attrs, [
      :title,
      :material_mode,
      :group_sizing,
      :max_group_size,
      :group_count,
      :timer_minutes
    ])
    |> validate_required([:title, :material_mode, :group_sizing, :max_group_size])
    |> validate_length(:title, max: 255, count: :codepoints)
    |> validate_inclusion(:material_mode, @material_modes)
    |> validate_inclusion(:group_sizing, @group_sizings)
    |> validate_number(:max_group_size, greater_than_or_equal_to: 2, less_than_or_equal_to: 12)
    |> validate_number(:group_count, greater_than_or_equal_to: 1, less_than_or_equal_to: 50)
    |> validate_number(:timer_minutes, greater_than_or_equal_to: 1, less_than_or_equal_to: 240)
    |> validate_group_count()
    |> check_constraint(:material_mode, name: :breakouts_material_mode)
    |> check_constraint(:group_sizing, name: :breakouts_group_sizing)
    |> check_constraint(:max_group_size, name: :breakouts_max_group_size)
    |> check_constraint(:group_count, name: :breakouts_group_count)
    |> check_constraint(:timer_minutes, name: :breakouts_timer_minutes)
  end

  @doc "A new breakout, in an event (`presentation_file_id`, `position`) or the library."
  def create_changeset(breakout, attrs, placement) do
    breakout
    |> change(
      Map.take(placement, [:user_id, :presentation_file_id, :position, :source_breakout_id])
    )
    |> put_change(:uuid, Ecto.UUID.generate())
    |> changeset(attrs)
    |> validate_required([:user_id])
  end

  def placement_changeset(breakout, attrs) do
    cast(breakout, attrs, [:position, :enabled])
  end

  defp validate_group_count(changeset) do
    if get_field(changeset, :group_sizing) == "group_count" do
      validate_required(changeset, [:group_count])
    else
      changeset
    end
  end

  def library?(%__MODULE__{presentation_file_id: nil}), do: true
  def library?(%__MODULE__{}), do: false
end
