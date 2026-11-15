defmodule Claper.Breakouts.Pieces.Text do
  @moduledoc "Typed text for the group to read. Its text lives on the piece (`body`)."
  @behaviour Claper.Breakouts.PieceType
  import Ecto.Changeset

  @impl true
  def kind, do: "text"

  @impl true
  def label, do: Gettext.gettext(ClaperWeb.Gettext, "Text")

  @impl true
  def answerable?, do: false

  @impl true
  def validate_piece(changeset), do: validate_required(changeset, [:body])

  @impl true
  def create_content(piece, _attrs), do: {:ok, piece}

  @impl true
  def update_content(piece, attrs) do
    piece
    |> Claper.Breakouts.Piece.changeset(Map.take(attrs, ["body", :body]))
    |> Claper.Repo.update()
  end

  @impl true
  def load(piece), do: piece

  @impl true
  def copy_content(_definition, piece), do: {:ok, piece}

  @impl true
  def validate_response(_definition, _params), do: {:error, "This piece is for reading only"}

  @impl true
  def describe_response(_definition, _response), do: []

  @impl true
  def summarize(_definition, _responses), do: %{}
end
