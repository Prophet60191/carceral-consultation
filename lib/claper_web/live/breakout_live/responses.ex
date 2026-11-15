defmodule ClaperWeb.BreakoutLive.Responses do
  @moduledoc """
  Turns a tap or keystroke on an interaction into the answer to save, from
  the answer shown now. Shared by breakout phones (`bk_*` events,
  `ClaperWeb.BreakoutLive.Phone`) and the intro page (`intro_*` events,
  `ClaperWeb.IntroLive.Answering`), so both answer the same way.

  `build(action, params, content, current)` returns `{:ok, response, opts}`
  (`opts`: `empty?: true` when the answer was cleared and should be taken
  back; `quiet: true` when errors shouldn't interrupt typing) or `:ignore`.
  """

  @actions ~w(poll quiz form word_add word_remove)

  def actions, do: @actions

  def build("poll", %{"opt" => opt}, content, current) do
    with {:ok, opt} <- to_id(opt) do
      chosen = Map.get(current || %{}, "options", [])

      chosen =
        cond do
          content.multiple and opt in chosen -> List.delete(chosen, opt)
          content.multiple -> chosen ++ [opt]
          true -> [opt]
        end

      {:ok, %{"options" => chosen}, empty?: chosen == []}
    else
      _ -> :ignore
    end
  end

  def build("quiz", %{"question" => q, "opt" => opt}, _content, current) do
    with {:ok, opt} <- to_id(opt), {:ok, q_id} <- to_id(q) do
      answers = Map.get(current || %{}, "answers", %{})
      q = Integer.to_string(q_id)
      chosen = Map.get(answers, q, [])
      chosen = if opt in chosen, do: List.delete(chosen, opt), else: chosen ++ [opt]
      answers = Map.put(answers, q, chosen)

      {:ok, %{"answers" => answers}, empty?: Enum.all?(Map.values(answers), &(&1 == []))}
    else
      _ -> :ignore
    end
  end

  def build("form", params, _content, _current) do
    fields = Map.get(params, "fields", %{})

    {:ok, %{"fields" => fields},
     quiet: true, empty?: Enum.all?(Map.values(fields), &(String.trim(to_string(&1)) == ""))}
  end

  def build("word_add", %{"word" => word}, _content, current) do
    words = Map.get(current || %{}, "words", [])
    {:ok, %{"words" => words ++ [word]}, []}
  end

  def build("word_remove", %{"word" => word}, _content, current) do
    words = Map.get(current || %{}, "words", []) |> List.delete(word)
    {:ok, %{"words" => words}, empty?: words == []}
  end

  def build(_action, _params, _content, _current), do: :ignore

  @doc "Tap values come from the browser: accept an integer or its digits only."
  def to_id(value) when is_integer(value), do: {:ok, value}

  def to_id(value) when is_binary(value) do
    case Integer.parse(value) do
      {id, ""} -> {:ok, id}
      _ -> :error
    end
  end

  def to_id(_value), do: :error
end
