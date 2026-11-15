defmodule Claper.Breakouts.PieceType do
  @moduledoc """
  The contract every breakout piece type meets (docs/BREAKOUT.md, decision 11:
  any interaction, present or future, can be a piece).

  Breakout code never names poll, quiz or any other type; it works only
  through these callbacks. To make a new interaction usable in breakouts:

    1. add a nullable `breakout_piece_id` column to its table (one migration,
       like the one that created breakouts) and a `piece_changeset/2` that
       validates its content without a slide;
    2. write a module implementing this behaviour;
    3. add the module to `@types` below.

  The web side (how a piece shows on a phone and on the presenter's screen)
  has its own, matching contract.
  """

  alias Claper.Breakouts.Piece

  @typedoc "The piece's content: the interaction record, or the piece itself for typed text."
  @type definition :: struct()

  @doc "Stored in `breakout_pieces.kind`."
  @callback kind() :: String.t()

  @doc "Whether people answer this piece (typed text and web content are only read)."
  @callback answerable?() :: boolean()

  @doc "Extra checks on the piece record itself (for typed text: it has text)."
  @callback validate_piece(Ecto.Changeset.t()) :: Ecto.Changeset.t()

  @doc "Creates the content for a new piece from the presenter's input."
  @callback create_content(Piece.t(), map()) :: {:ok, definition()} | {:error, Ecto.Changeset.t()}

  @doc "Changes a piece's content from the presenter's input."
  @callback update_content(definition(), map()) ::
              {:ok, definition()} | {:error, Ecto.Changeset.t()}

  @doc "Loads a piece's content, ready to show."
  @callback load(Piece.t()) :: definition() | nil

  @doc "Copies a piece's content onto another piece (library and event copies). No answers are copied."
  @callback copy_content(definition(), Piece.t()) :: {:ok, definition()} | {:error, term()}

  @doc """
  Checks an answer against the piece's content and returns the response to
  store. Partial answers are fine: groups work at their own pace.
  """
  @callback validate_response(definition(), map()) :: {:ok, map()} | {:error, String.t()}

  @doc """
  A stored response as plain text for exports: `{label, text}` pairs, where
  `label` names the part (a question or field) or is nil for a single answer.
  """
  @callback describe_response(definition(), map()) :: [{String.t() | nil, String.t()}]

  @doc "Sums up a list of stored responses (each a map) for results and reporting back."
  @callback summarize(definition(), [map()]) :: map()

  @types [
    Claper.Breakouts.Pieces.Text,
    Claper.Breakouts.Pieces.Poll,
    Claper.Breakouts.Pieces.Quiz,
    Claper.Breakouts.Pieces.Form,
    Claper.Breakouts.Pieces.WordCloud,
    Claper.Breakouts.Pieces.Embed
  ]

  @doc "The name shown to the presenter, e.g. \"Poll\"."
  @callback label() :: String.t()

  @doc "Every piece type module."
  def types, do: @types

  @doc "Every valid `kind`."
  def kinds, do: Enum.map(@types, & &1.kind())

  @doc "The module for a kind, or nil."
  def module_for(kind), do: Enum.find(@types, &(&1.kind() == kind))

  @doc """
  The module for a piece (or an intro page block with an interaction kind,
  docs/INTRO.md); raises for an unknown kind (it cannot be stored).
  """
  def module_for!(%{kind: kind}) do
    module_for(kind) || raise ArgumentError, "unknown breakout piece kind: #{inspect(kind)}"
  end

  @doc """
  Piece-level checks shared by every type, then the type's own: a piece that
  nobody answers is always "individual" and never shared.
  """
  def validate_piece(changeset) do
    case module_for(Ecto.Changeset.get_field(changeset, :kind)) do
      nil ->
        changeset

      module ->
        changeset
        |> then(fn cs ->
          if module.answerable?(),
            do: cs,
            else: Ecto.Changeset.change(cs, answer_scope: "individual", visible_to_group: false)
        end)
        |> module.validate_piece()
    end
  end
end
