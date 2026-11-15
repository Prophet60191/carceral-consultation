defmodule Claper.Breakouts.Pieces.Form do
  @moduledoc """
  A form: one or more fields to write in.
  Response: `%{"fields" => %{"<field name>" => "text"}}`; blank fields are
  left out (unfinished work is fine).
  """
  @behaviour Claper.Breakouts.PieceType
  alias Claper.Breakouts.Pieces.Content
  alias Claper.Forms.Form

  @max_length 5_000

  @impl true
  def kind, do: "form"

  @impl true
  def label, do: Gettext.gettext(ClaperWeb.Gettext, "Form")

  @impl true
  def answerable?, do: true

  @impl true
  def validate_piece(changeset), do: changeset

  @impl true
  def create_content(piece, attrs), do: Content.insert(Form, piece, attrs)

  @impl true
  def update_content(content, attrs), do: Content.update(content, attrs)

  @impl true
  def load(piece), do: Content.load(Form, piece)

  @impl true
  def copy_content(%Form{} = form, piece) do
    create_content(piece, %{
      title: form.title,
      fields: Enum.map(form.fields, &%{name: &1.name, type: &1.type, required: &1.required})
    })
  end

  @impl true
  def validate_response(%Form{} = form, %{"fields" => fields}) when is_map(fields) do
    names = MapSet.new(form.fields, & &1.name)

    cond do
      not Enum.all?(fields, fn {k, v} -> MapSet.member?(names, k) and is_binary(v) end) ->
        {:error, "Unknown field"}

      true ->
        kept =
          fields
          |> Enum.map(fn {k, v} -> {k, v |> String.trim() |> String.slice(0, @max_length)} end)
          |> Enum.reject(fn {_k, v} -> v == "" end)
          |> Map.new()

        if kept == %{}, do: {:error, "Write something first"}, else: {:ok, %{"fields" => kept}}
    end
  end

  def validate_response(_form, _params), do: {:error, "Write something first"}

  @impl true
  def describe_response(%Form{} = form, %{"fields" => fields}) do
    form.fields
    |> Enum.map(&{&1.name, Map.get(fields, &1.name)})
    |> Enum.filter(fn {_name, text} -> is_binary(text) end)
  end

  def describe_response(_form, _response), do: []

  @impl true
  def summarize(%Form{} = form, responses) do
    %{
      total: length(responses),
      fields:
        Enum.map(form.fields, fn f ->
          %{
            name: f.name,
            answers:
              responses |> Enum.map(&get_in(&1, ["fields", f.name])) |> Enum.reject(&is_nil/1)
          }
        end)
    }
  end
end
