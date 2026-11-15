defmodule Claper.Breakouts.Pieces.WordCloud do
  @moduledoc """
  A word cloud: each answer is up to `max_entries` words.
  Response: `%{"words" => ["word", ...]}`, cleaned and de-duplicated the same
  way word cloud entries are (`Claper.WordClouds.Entry`).
  """
  @behaviour Claper.Breakouts.PieceType
  alias Claper.Breakouts.Pieces.Content
  alias Claper.WordClouds.{Entry, WordCloud}

  @impl true
  def kind, do: "word_cloud"

  @impl true
  def label, do: Gettext.gettext(ClaperWeb.Gettext, "Word cloud")

  @impl true
  def answerable?, do: true

  @impl true
  def validate_piece(changeset), do: changeset

  @impl true
  def create_content(piece, attrs), do: Content.insert(WordCloud, piece, attrs)

  @impl true
  def update_content(content, attrs), do: Content.update(content, attrs)

  @impl true
  def load(piece), do: Content.load(WordCloud, piece)

  @impl true
  def copy_content(%WordCloud{} = word_cloud, piece) do
    create_content(piece, %{
      title: word_cloud.title,
      show_results: word_cloud.show_results,
      max_entries: word_cloud.max_entries
    })
  end

  @impl true
  def validate_response(%WordCloud{} = word_cloud, %{"words" => words}) when is_list(words) do
    if Enum.all?(words, &is_binary/1) do
      kept =
        words
        |> Enum.map(&Entry.word/1)
        |> Enum.reject(&(&1 == ""))
        |> Enum.uniq_by(&Entry.normalize/1)

      cond do
        kept == [] -> {:error, "Add a word first"}
        length(kept) > word_cloud.max_entries -> {:error, "Too many words"}
        true -> {:ok, %{"words" => kept}}
      end
    else
      {:error, "Add a word first"}
    end
  end

  def validate_response(_word_cloud, _params), do: {:error, "Add a word first"}

  @impl true
  def describe_response(%WordCloud{}, %{"words" => words}), do: [{nil, Enum.join(words, ", ")}]
  def describe_response(_word_cloud, _response), do: []

  @impl true
  def summarize(%WordCloud{}, responses) do
    words =
      responses
      |> Enum.flat_map(&Map.get(&1, "words", []))
      |> Enum.group_by(&Entry.normalize/1)
      |> Enum.map(fn {key, [first | _] = all} -> %{key: key, text: first, count: length(all)} end)
      |> Enum.sort_by(&{-&1.count, &1.key})

    %{total: length(responses), words: words}
  end
end
