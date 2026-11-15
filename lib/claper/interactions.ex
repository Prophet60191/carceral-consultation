defmodule Claper.Interactions do
  alias Claper.Polls
  alias Claper.Forms
  alias Claper.Embeds
  alias Claper.Events
  alias Claper.Presentations
  alias Claper.Quizzes
  alias Claper.WordClouds
  import Ecto.Query, warn: false

  @type interaction ::
          Polls.Poll
          | Forms.Form
          | Embeds.Embed
          | Quizzes.Quiz
          | WordClouds.WordCloud
          | Claper.Breakouts.Breakout

  def get_number_total_interactions(presentation_file_id) do
    from(p in Polls.Poll,
      where: p.presentation_file_id == ^presentation_file_id,
      select: count(p.id)
    )
    |> Claper.Repo.one()
    |> Kernel.+(
      from(f in Forms.Form,
        where: f.presentation_file_id == ^presentation_file_id,
        select: count(f.id)
      )
      |> Claper.Repo.one()
    )
    |> Kernel.+(
      from(e in Embeds.Embed,
        where: e.presentation_file_id == ^presentation_file_id,
        select: count(e.id)
      )
      |> Claper.Repo.one()
    )
    |> Kernel.+(
      from(q in Quizzes.Quiz,
        where: q.presentation_file_id == ^presentation_file_id,
        select: count(q.id)
      )
      |> Claper.Repo.one()
    )
    |> Kernel.+(
      from(w in WordClouds.WordCloud,
        where: w.presentation_file_id == ^presentation_file_id,
        select: count(w.id)
      )
      |> Claper.Repo.one()
    )
    |> Kernel.+(
      from(b in Claper.Breakouts.Breakout,
        where: b.presentation_file_id == ^presentation_file_id,
        select: count(b.id)
      )
      |> Claper.Repo.one()
    )
  end

  def get_active_interaction(event, position) do
    with {:ok, interactions} <- get_interactions_at_position(event, position) do
      interactions |> Enum.filter(&(&1.enabled == true)) |> List.first()
    end
  end

  def get_interactions_at_position(
        %Events.Event{
          presentation_file: %Presentations.PresentationFile{id: presentation_file_id}
        } = event,
        position,
        broadcast \\ false
      ) do
    with polls <- Polls.list_polls_at_position(presentation_file_id, position),
         forms <- Forms.list_forms_at_position(presentation_file_id, position),
         embeds <- Embeds.list_embeds_at_position(presentation_file_id, position),
         quizzes <- Quizzes.list_quizzes_at_position(presentation_file_id, position),
         word_clouds <- WordClouds.list_word_clouds_at_position(presentation_file_id, position),
         breakouts <- Claper.Breakouts.list_breakouts_at_position(presentation_file_id, position) do
      interactions =
        (polls ++ forms ++ embeds ++ quizzes ++ word_clouds ++ breakouts)
        |> sort_on_slide()

      if broadcast do
        active_interaction = interactions |> Enum.filter(&(&1.enabled == true)) |> List.first()

        Phoenix.PubSub.broadcast(
          Claper.PubSub,
          "event:#{event.uuid}",
          {:current_interaction, active_interaction}
        )
      end

      {:ok, interactions}
    end
  end

  @doc """
  Orders a slide's interactions: the presenter's order first (`slide_order`),
  then any not ordered yet, oldest first.
  """
  def sort_on_slide(interactions) do
    # Enum.sort_by is stable: ties keep the order they were listed in.
    Enum.sort_by(interactions, fn %{slide_order: order, inserted_at: at} ->
      {if(is_nil(order), do: 1, else: 0), order || 0, NaiveDateTime.to_gregorian_seconds(at)}
    end)
  end

  @doc "The kind of an interaction, as used in the manage screen's events."
  def type_key(%Polls.Poll{}), do: "poll"
  def type_key(%Forms.Form{}), do: "form"
  def type_key(%Embeds.Embed{}), do: "embed"
  def type_key(%Quizzes.Quiz{}), do: "quiz"
  def type_key(%WordClouds.WordCloud{}), do: "word_cloud"
  def type_key(%Claper.Breakouts.Breakout{}), do: "breakout"
  def type_key(_), do: nil

  @schemas %{
    "poll" => Polls.Poll,
    "form" => Forms.Form,
    "embed" => Embeds.Embed,
    "quiz" => Quizzes.Quiz,
    "word_cloud" => WordClouds.WordCloud,
    "breakout" => Claper.Breakouts.Breakout
  }

  @doc """
  Saves the presenter's order for the interactions on one slide. `keys` is
  every interaction on that slide, as `{type_key, id}`, in the new order;
  anything else (a missing, extra or foreign interaction) is refused with
  `{:error, :mismatch}`, so a stale screen cannot scramble the slide.
  """
  def reorder(%Events.Event{} = event, position, keys) when is_list(keys) do
    {:ok, current} = get_interactions_at_position(event, position)
    current_keys = MapSet.new(current, &{type_key(&1), &1.id})

    if length(keys) == MapSet.size(current_keys) and MapSet.new(keys) == current_keys do
      Claper.Repo.transaction(fn ->
        keys
        |> Enum.with_index()
        |> Enum.each(fn {{type, id}, index} ->
          from(i in Map.fetch!(@schemas, type), where: i.id == ^id)
          |> Claper.Repo.update_all(set: [slide_order: index])
        end)
      end)

      get_interactions_at_position(event, position)
    else
      {:error, :mismatch}
    end
  end

  @doc "Sets one interaction's place on its slide (nil: after the ordered ones)."
  def put_slide_order(interaction, order) do
    from(i in interaction.__struct__, where: i.id == ^interaction.id)
    |> Claper.Repo.update_all(set: [slide_order: order])

    %{interaction | slide_order: order}
  end

  @doc """
  Moves an interaction to another slide position.

  The interaction is disabled when moved so it doesn't stay live on a slide
  the audience is not looking at. Returns `{:ok, interaction}` (a no-op when
  the position is unchanged) or `{:error, :invalid_position}`.
  """
  def move_interaction(
        %Events.Event{
          presentation_file: %Presentations.PresentationFile{} = presentation_file
        } = event,
        interaction,
        to
      )
      when is_integer(to) do
    count = presentation_file.length || 0

    cond do
      to < 0 or to >= count ->
        {:error, :invalid_position}

      to == interaction.position ->
        {:ok, interaction}

      # On its new slide it goes after the ones already ordered there.
      true ->
        with {:ok, moved} <- do_move_interaction(event.uuid, interaction, to),
             do: {:ok, put_slide_order(moved, nil)}
    end
  end

  defp do_move_interaction(event_uuid, %Polls.Poll{} = poll, to),
    do: Polls.update_poll(event_uuid, poll, %{position: to, enabled: false})

  defp do_move_interaction(event_uuid, %Forms.Form{} = form, to),
    do: Forms.update_form(event_uuid, form, %{position: to, enabled: false})

  defp do_move_interaction(event_uuid, %Embeds.Embed{} = embed, to),
    do: Embeds.update_embed(event_uuid, embed, %{position: to, enabled: false})

  # Quiz.changeset requires quiz_questions via cast_assoc, so they must be
  # loaded even though the move doesn't touch them.
  defp do_move_interaction(event_uuid, %Quizzes.Quiz{} = quiz, to) do
    quiz = Claper.Repo.preload(quiz, quiz_questions: :quiz_question_opts)
    Quizzes.update_quiz(event_uuid, quiz, %{position: to, enabled: false})
  end

  defp do_move_interaction(event_uuid, %WordClouds.WordCloud{} = word_cloud, to),
    do: WordClouds.update_word_cloud(event_uuid, word_cloud, %{position: to, enabled: false})

  defp do_move_interaction(_event_uuid, %Claper.Breakouts.Breakout{} = breakout, to),
    do: Claper.Breakouts.set_placement(breakout, %{position: to, enabled: false})

  def enable_interaction(interaction) do
    Ecto.Multi.new()
    |> Ecto.Multi.run(:disable_polls, fn _repo, _ ->
      {count, _} = Polls.disable_all(interaction.presentation_file_id, interaction.position)
      {:ok, count}
    end)
    |> Ecto.Multi.run(:disable_forms, fn _repo, _ ->
      {count, _} = Forms.disable_all(interaction.presentation_file_id, interaction.position)
      {:ok, count}
    end)
    |> Ecto.Multi.run(:disable_embeds, fn _repo, _ ->
      {count, _} = Embeds.disable_all(interaction.presentation_file_id, interaction.position)
      {:ok, count}
    end)
    |> Ecto.Multi.run(:disable_quizzes, fn _repo, _ ->
      {count, _} = Quizzes.disable_all(interaction.presentation_file_id, interaction.position)
      {:ok, count}
    end)
    |> Ecto.Multi.run(:disable_word_clouds, fn _repo, _ ->
      {count, _} = WordClouds.disable_all(interaction.presentation_file_id, interaction.position)
      {:ok, count}
    end)
    |> Ecto.Multi.run(:enable_interaction, fn _repo, _ ->
      set_enabled(interaction)
    end)
    |> Claper.Repo.transaction()
    |> case do
      {:ok, _} -> :ok
      {:error, _, reason, _} -> {:error, reason}
    end
  end

  @doc """
  Starts the big screen from an interaction's own "Show the results on the
  big screen" choice (`results_on_screen`), right after it is turned on
  (Jose, 2026-11-14). The choice itself is never changed here: the manage
  screen's switch only changes what the big screen shows for this run.

  - Poll, word cloud, form: the presentation's results switch
    (`state.poll_visible`) is set to the choice and the change is broadcast.
  - Quiz: its reveal (`show_results`) is set to the choice.
  - Anything else is left as it is.

  Returns `{interaction, state}` as they now are.
  """
  def show_planned_results(%Quizzes.Quiz{} = quiz, state) do
    from(q in Quizzes.Quiz, where: q.id == ^quiz.id)
    |> Claper.Repo.update_all(set: [show_results: quiz.results_on_screen])

    {%{quiz | show_results: quiz.results_on_screen}, state}
  end

  def show_planned_results(%schema{} = interaction, state)
      when schema in [Polls.Poll, WordClouds.WordCloud, Forms.Form] do
    if state.poll_visible == interaction.results_on_screen do
      {interaction, state}
    else
      {:ok, state} =
        Presentations.update_presentation_state(state, %{
          poll_visible: interaction.results_on_screen
        })

      {interaction, state}
    end
  end

  def show_planned_results(interaction, state), do: {interaction, state}

  defp set_enabled(%Polls.Poll{} = interaction) do
    Polls.set_enabled(interaction.id)
  end

  defp set_enabled(%Forms.Form{} = interaction) do
    Forms.set_enabled(interaction.id)
  end

  defp set_enabled(%Embeds.Embed{} = interaction) do
    Embeds.set_enabled(interaction.id)
  end

  defp set_enabled(%Quizzes.Quiz{} = interaction) do
    Quizzes.set_enabled(interaction.id)
  end

  defp set_enabled(%WordClouds.WordCloud{} = interaction) do
    WordClouds.set_enabled(interaction.id)
  end

  def disable_interaction(%Polls.Poll{} = interaction) do
    Polls.set_disabled(interaction.id)
  end

  def disable_interaction(%Forms.Form{} = interaction) do
    Forms.set_disabled(interaction.id)
  end

  def disable_interaction(%Embeds.Embed{} = interaction) do
    Embeds.set_disabled(interaction.id)
  end

  def disable_interaction(%Quizzes.Quiz{} = interaction) do
    Quizzes.set_disabled(interaction.id)
  end

  def disable_interaction(%WordClouds.WordCloud{} = interaction) do
    WordClouds.set_disabled(interaction.id)
  end
end
