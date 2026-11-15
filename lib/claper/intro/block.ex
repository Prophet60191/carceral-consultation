defmodule Claper.Intro.Block do
  @moduledoc """
  One block of an intro page (docs/INTRO.md, decision 2). `data` holds the
  block's own fields, checked per kind by `changeset/2`:

    * `heading` — `text`
    * `text` — `body` (line breaks kept)
    * `image` — `src` (an uploaded file under /uploads/intro/), `alt`, `caption`
    * `stat` — `value` (the big number), `label`
    * `agenda` — `items`: rows of `time` (optional) and `title`
    * `link` — `label`, `url` (http or https only)
    * `divider` — nothing
    * `poll`, `quiz`, `form`, `word_cloud`, `embed` — an interaction
      (decision 11): its content lives in the interaction's own table, linked
      by `intro_block_id`, and works through the breakout piece types
      (`Claper.Breakouts.PieceType`). `data` holds only `show_answers` for a
      form (decision 15: written answers on the big screen, default off).
  """
  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{}

  @interaction_kinds ~w(poll quiz form word_cloud embed)
  @kinds ~w(heading text image stat agenda link divider) ++ @interaction_kinds
  @max_agenda_rows 30

  schema "intro_blocks" do
    field :position, :integer, default: 0
    field :kind, :string
    field :data, :map, default: %{}

    belongs_to :intro_page, Claper.Intro.Page

    timestamps()
  end

  def kinds, do: @kinds

  @doc "The kinds that are interactions (their content is an interaction record)."
  def interaction_kinds, do: @interaction_kinds

  def interaction?(%{kind: kind}), do: kind in @interaction_kinds

  @doc "A block with its fields checked for its kind; `data` is cleaned up."
  def changeset(block, attrs) do
    block
    |> cast(attrs, [:kind, :position])
    |> validate_required([:kind])
    |> validate_inclusion(:kind, @kinds)
    |> check_constraint(:kind, name: :intro_blocks_kind)
    |> put_data(attrs)
  end

  defp put_data(changeset, attrs) do
    kind = get_field(changeset, :kind)
    raw = attrs |> Map.get(:data, Map.get(attrs, "data", %{})) |> stringify()

    case kind in @kinds && clean(kind, raw) do
      {:ok, data} -> put_change(changeset, :data, data)
      {:error, field, message} -> add_error(changeset, field, message)
      _ -> changeset
    end
  end

  # Each kind's fields: trimmed, limited, required ones present.
  defp clean("heading", d),
    do: with({:ok, text} <- req(d, "text", 120, :text), do: {:ok, %{"text" => text}})

  defp clean("text", d),
    do: with({:ok, body} <- req(d, "body", 5000, :body), do: {:ok, %{"body" => body}})

  defp clean("image", d) do
    with {:ok, src} <- req(d, "src", 500, :src),
         :ok <- upload_path(src),
         {:ok, alt} <- opt(d, "alt", 200, :alt),
         {:ok, caption} <- opt(d, "caption", 200, :caption) do
      {:ok, %{"src" => src, "alt" => alt, "caption" => caption}}
    end
  end

  defp clean("stat", d) do
    with {:ok, value} <- req(d, "value", 40, :value),
         {:ok, label} <- req(d, "label", 160, :label) do
      {:ok, %{"value" => value, "label" => label}}
    end
  end

  defp clean("agenda", d) do
    rows =
      d
      |> Map.get("items", [])
      |> rows()
      |> Enum.map(fn row ->
        %{"time" => trim(row["time"]), "title" => trim(row["title"])}
      end)
      |> Enum.reject(&(&1["time"] == "" and &1["title"] == ""))

    cond do
      rows == [] ->
        {:error, :items, "add at least one item"}

      length(rows) > @max_agenda_rows ->
        {:error, :items, "can have at most #{@max_agenda_rows} items"}

      Enum.any?(rows, &(&1["title"] == "")) ->
        {:error, :items, "every item needs a title"}

      Enum.any?(rows, &(String.length(&1["title"]) > 160 or String.length(&1["time"]) > 20)) ->
        {:error, :items, "an item is too long"}

      true ->
        {:ok, %{"items" => rows}}
    end
  end

  defp clean("link", d) do
    with {:ok, label} <- req(d, "label", 80, :label),
         {:ok, url} <- req(d, "url", 2000, :url),
         :ok <- web_url(url) do
      {:ok, %{"label" => label, "url" => url}}
    end
  end

  defp clean("divider", _d), do: {:ok, %{}}

  defp clean("form", d),
    do: {:ok, %{"show_answers" => d["show_answers"] in [true, "true", "on", "1"]}}

  defp clean(kind, _d) when kind in @interaction_kinds, do: {:ok, %{}}

  defp req(d, key, max, field) do
    case trim(d[key]) do
      "" ->
        {:error, field, "can't be blank"}

      value ->
        if String.length(value) > max,
          do: {:error, field, "should be at most #{max} characters"},
          else: {:ok, value}
    end
  end

  defp opt(d, key, max, field) do
    value = trim(d[key])

    if String.length(value) > max,
      do: {:error, field, "should be at most #{max} characters"},
      else: {:ok, value}
  end

  defp web_url(url) do
    case URI.parse(url) do
      %URI{scheme: scheme, host: host}
      when scheme in ["http", "https"] and is_binary(host) and host != "" ->
        :ok

      _ ->
        {:error, :url, "must be a web address starting with http:// or https://"}
    end
  end

  # Images come from this app's own upload folder only.
  defp upload_path("/uploads/intro/" <> name) do
    if name =~ ~r/\A[a-f0-9-]+\.(png|jpg|jpeg|webp|gif)\z/,
      do: :ok,
      else: {:error, :src, "is not an uploaded image"}
  end

  defp upload_path(_), do: {:error, :src, "is not an uploaded image"}

  defp rows(items) when is_list(items), do: Enum.map(items, &stringify/1)

  defp rows(items) when is_map(items) do
    items
    |> Enum.sort_by(fn {k, _} -> String.to_integer(to_string(k)) end)
    |> Enum.map(fn {_, v} -> stringify(v) end)
  rescue
    ArgumentError -> []
  end

  defp rows(_), do: []

  defp stringify(map) when is_map(map), do: Map.new(map, fn {k, v} -> {to_string(k), v} end)
  defp stringify(_), do: %{}

  defp trim(nil), do: ""
  defp trim(value) when is_binary(value), do: String.trim(value)
  defp trim(value), do: value |> to_string() |> String.trim()
end
