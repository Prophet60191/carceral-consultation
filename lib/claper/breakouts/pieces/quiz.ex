defmodule Claper.Breakouts.Pieces.Quiz do
  @moduledoc """
  A quiz: questions with marked right answers.
  Response: `%{"answers" => %{"<question_id>" => [opt_id, ...]}}`; questions
  left unanswered are simply absent (unfinished work is fine).
  """
  @behaviour Claper.Breakouts.PieceType
  alias Claper.Breakouts.Pieces.Content
  alias Claper.Quizzes.Quiz

  @impl true
  def kind, do: "quiz"

  @impl true
  def label, do: Gettext.gettext(ClaperWeb.Gettext, "Quiz")

  @impl true
  def answerable?, do: true

  @impl true
  def validate_piece(changeset), do: changeset

  @impl true
  def create_content(piece, attrs), do: Content.insert(Quiz, piece, attrs)

  @impl true
  def update_content(content, attrs), do: Content.update(content, attrs)

  @impl true
  def load(piece), do: Content.load(Quiz, piece, quiz_questions: :quiz_question_opts)

  @impl true
  def copy_content(%Quiz{} = quiz, piece) do
    create_content(piece, %{
      title: quiz.title,
      show_results: quiz.show_results,
      quiz_questions:
        Enum.map(quiz.quiz_questions, fn q ->
          %{
            content: q.content,
            type: q.type,
            quiz_question_opts:
              Enum.map(q.quiz_question_opts, &%{content: &1.content, is_correct: &1.is_correct})
          }
        end)
    })
  end

  @impl true
  def validate_response(%Quiz{} = quiz, %{"answers" => answers}) when is_map(answers) do
    questions =
      Map.new(quiz.quiz_questions, &{&1.id, MapSet.new(&1.quiz_question_opts, fn o -> o.id end)})

    answers
    |> Enum.reduce_while({:ok, %{}}, fn {qid, opts}, {:ok, acc} ->
      with {:ok, [id]} <- Content.ids([qid]),
           {:ok, valid} <- Map.fetch(questions, id),
           {:ok, ids} <- Content.ids(opts),
           true <- Enum.all?(ids, &MapSet.member?(valid, &1)) do
        if ids == [],
          do: {:cont, {:ok, acc}},
          else: {:cont, {:ok, Map.put(acc, Integer.to_string(id), Enum.sort(ids))}}
      else
        _ -> {:halt, {:error, "Unknown answer"}}
      end
    end)
    |> case do
      {:ok, map} when map_size(map) == 0 -> {:error, "Answer at least one question"}
      {:ok, map} -> {:ok, %{"answers" => map}}
      error -> error
    end
  end

  def validate_response(_quiz, _params), do: {:error, "Answer at least one question"}

  @impl true
  def describe_response(%Quiz{} = quiz, %{"answers" => answers}) do
    Enum.flat_map(quiz.quiz_questions, fn q ->
      case Map.get(answers, Integer.to_string(q.id)) do
        nil ->
          []

        chosen ->
          names = Map.new(q.quiz_question_opts, &{&1.id, &1.content})

          correct =
            q.quiz_question_opts
            |> Enum.filter(& &1.is_correct)
            |> Enum.map(& &1.id)
            |> Enum.sort()

          verdict = if Enum.sort(chosen) == correct, do: "right", else: "wrong"
          text = chosen |> Enum.map(&Map.get(names, &1, "?")) |> Enum.join("; ")
          [{q.content, "#{text} (#{verdict})"}]
      end
    end)
  end

  def describe_response(_quiz, _response), do: []

  @impl true
  def summarize(%Quiz{} = quiz, responses) do
    %{
      total: length(responses),
      questions:
        Enum.map(quiz.quiz_questions, fn q ->
          key = Integer.to_string(q.id)
          chosen = Enum.map(responses, &get_in(&1, ["answers", key]))
          answered = Enum.reject(chosen, &is_nil/1)
          counts = answered |> List.flatten() |> Enum.frequencies()

          correct =
            q.quiz_question_opts
            |> Enum.filter(& &1.is_correct)
            |> Enum.map(& &1.id)
            |> Enum.sort()

          %{
            id: q.id,
            content: q.content,
            answered: length(answered),
            correct: Enum.count(answered, &(&1 == correct)),
            options:
              Enum.map(
                q.quiz_question_opts,
                &%{
                  id: &1.id,
                  content: &1.content,
                  is_correct: &1.is_correct,
                  count: Map.get(counts, &1.id, 0)
                }
              )
          }
        end)
    }
  end
end
