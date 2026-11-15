defmodule Claper.Breakouts.Pieces.Content do
  @moduledoc """
  Shared helpers for piece types whose content is an interaction record
  linked to its owner: a breakout piece (`breakout_piece_id`) or an intro
  page block (`intro_block_id`, docs/INTRO.md). The piece type modules work
  the same for both.
  """
  import Ecto.Query
  alias Claper.Repo

  @doc "The link column for an owner."
  def owner_field(%Claper.Breakouts.Piece{}), do: :breakout_piece_id
  def owner_field(%Claper.Intro.Block{}), do: :intro_block_id

  @doc "Inserts the content for an owner with the schema's `piece_changeset/2`."
  def insert(schema, owner, attrs) do
    schema
    |> struct([{owner_field(owner), owner.id}])
    |> schema.piece_changeset(attrs)
    |> Repo.insert()
  end

  @doc "A content changeset needs an owner (a breakout piece or an intro block)."
  def require_owner(changeset) do
    if Ecto.Changeset.get_field(changeset, :breakout_piece_id) ||
         Ecto.Changeset.get_field(changeset, :intro_block_id),
       do: changeset,
       else: Ecto.Changeset.add_error(changeset, :breakout_piece_id, "can't be blank")
  end

  @doc "Changes a piece's content with the schema's `piece_changeset/2`."
  def update(%schema{} = content, attrs) do
    content
    |> schema.piece_changeset(attrs)
    |> Repo.update()
  end

  @doc "Loads the content linked to an owner, with its preloads."
  def load(schema, owner, preloads \\ []) do
    field = owner_field(owner)

    from(c in schema, where: field(c, ^field) == ^owner.id)
    |> Repo.one()
    |> case do
      nil -> nil
      content -> Repo.preload(content, preloads)
    end
  end

  @doc "A list of ids from a response value (ids may arrive as strings)."
  def ids(value) when is_list(value) do
    Enum.reduce_while(value, {:ok, []}, fn v, {:ok, acc} ->
      case int(v) do
        {:ok, id} -> {:cont, {:ok, [id | acc]}}
        :error -> {:halt, :error}
      end
    end)
    |> case do
      {:ok, ids} -> {:ok, ids |> Enum.reverse() |> Enum.uniq()}
      :error -> :error
    end
  end

  def ids(_value), do: :error

  defp int(v) when is_integer(v), do: {:ok, v}

  defp int(v) when is_binary(v) do
    case Integer.parse(v) do
      {i, ""} -> {:ok, i}
      _ -> :error
    end
  end

  defp int(_v), do: :error
end
