defmodule Claper.Breakouts.Pieces.Poll do
  @moduledoc """
  A poll: pick one answer, or several when the poll allows it.
  Response: `%{"options" => [poll_opt_id, ...]}`.
  """
  @behaviour Claper.Breakouts.PieceType
  alias Claper.Breakouts.Pieces.Content
  alias Claper.Polls.Poll

  @impl true
  def kind, do: "poll"

  @impl true
  def label, do: Gettext.gettext(ClaperWeb.Gettext, "Poll")

  @impl true
  def answerable?, do: true

  @impl true
  def validate_piece(changeset), do: changeset

  @impl true
  def create_content(piece, attrs), do: Content.insert(Poll, piece, attrs)

  @impl true
  def update_content(content, attrs), do: Content.update(content, attrs)

  @impl true
  def load(piece), do: Content.load(Poll, piece, :poll_opts)

  @impl true
  def copy_content(%Poll{} = poll, piece) do
    create_content(piece, %{
      title: poll.title,
      multiple: poll.multiple,
      show_results: poll.show_results,
      poll_opts: Enum.map(poll.poll_opts, &%{content: &1.content})
    })
  end

  @impl true
  def validate_response(%Poll{} = poll, %{"options" => options}) do
    valid = MapSet.new(poll.poll_opts, & &1.id)

    with {:ok, ids} <- Content.ids(options),
         true <- ids != [] or {:error, "Choose an answer"},
         true <- poll.multiple || length(ids) == 1 || {:error, "Choose one answer"},
         true <- Enum.all?(ids, &MapSet.member?(valid, &1)) || {:error, "Unknown answer"} do
      {:ok, %{"options" => Enum.sort(ids)}}
    else
      :error -> {:error, "Unknown answer"}
      {:error, _} = error -> error
    end
  end

  def validate_response(_poll, _params), do: {:error, "Choose an answer"}

  @impl true
  def describe_response(%Poll{} = poll, %{"options" => ids}) do
    names = Map.new(poll.poll_opts, &{&1.id, &1.content})
    [{nil, ids |> Enum.map(&Map.get(names, &1, "?")) |> Enum.join("; ")}]
  end

  def describe_response(_poll, _response), do: []

  @impl true
  def summarize(%Poll{} = poll, responses) do
    counts = responses |> Enum.flat_map(&Map.get(&1, "options", [])) |> Enum.frequencies()

    %{
      total: length(responses),
      options:
        Enum.map(
          poll.poll_opts,
          &%{id: &1.id, content: &1.content, count: Map.get(counts, &1.id, 0)}
        )
    }
  end
end
