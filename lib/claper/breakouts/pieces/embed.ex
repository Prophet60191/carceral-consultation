defmodule Claper.Breakouts.Pieces.Embed do
  @moduledoc "Web content (a website, video or slides) for the group to look at."
  @behaviour Claper.Breakouts.PieceType
  alias Claper.Breakouts.Pieces.Content
  alias Claper.Embeds.Embed

  @impl true
  def kind, do: "embed"

  @impl true
  def label, do: Gettext.gettext(ClaperWeb.Gettext, "Web content")

  @impl true
  def answerable?, do: false

  @impl true
  def validate_piece(changeset), do: changeset

  @impl true
  def create_content(piece, attrs), do: Content.insert(Embed, piece, attrs)

  @impl true
  def update_content(content, attrs), do: Content.update(content, attrs)

  @impl true
  def load(piece), do: Content.load(Embed, piece)

  @impl true
  def copy_content(%Embed{} = embed, piece) do
    create_content(piece, %{title: embed.title, content: embed.content, provider: embed.provider})
  end

  @impl true
  def validate_response(_definition, _params), do: {:error, "This piece is for viewing only"}

  @impl true
  def describe_response(_definition, _response), do: []

  @impl true
  def summarize(_definition, _responses), do: %{}
end
