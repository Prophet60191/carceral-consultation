defmodule ClaperWeb.BreakoutLive.PieceEditor do
  @moduledoc """
  Lets the existing interaction editors (poll, quiz, form, word cloud, web
  content) also edit a breakout piece (docs/BREAKOUT.md, decision 11).

  The builder passes `piece_target` to an editor:

    * `{:new, packet}` — create a new piece of that kind at the end of the packet
    * `{:edit, piece}` — change that piece's content
    * `{:intro_new, page}` / `{:intro_edit, block}` — the same on an intro
      page (docs/INTRO.md, decision 11): there the answers are always each
      person's, so the "Group answer" box is not shown, and a form gets
      `big_screen_choice/1` instead (decision 15)

  Without it (`nil`, the default) the editor works on a slide as before. In
  piece mode an editor saves through `save/5` and hides what only makes sense
  on a slide (delete, which the builder does, and slide-only options).

  Editors of answerable pieces also show `answer_choice/1`, the "Group
  answer" checkbox: ticked, the group's note-taker answers once for the
  group; unticked, each person answers. It is saved with the content.
  """
  use Phoenix.Component
  import Phoenix.LiveView, only: [push_navigate: 2, put_flash: 3]
  use Gettext, backend: ClaperWeb.Gettext

  alias Claper.Breakouts

  @doc "True when the editor is editing a breakout piece."
  def piece_mode?(assigns), do: not is_nil(Map.get(assigns, :piece_target))

  @doc """
  The "Group answer" checkbox for an answerable piece's editor. Its value
  comes back as `params["breakout"]`, which the editor passes to `save/5`.
  """
  attr :piece_target, :any, required: true

  def answer_choice(%{piece_target: {target, _}} = assigns)
      when target in [:intro_new, :intro_edit] do
    ~H"""
    """
  end

  def answer_choice(assigns) do
    group? =
      case assigns.piece_target do
        {:edit, %{answer_scope: scope}} -> scope == "group"
        _ -> false
      end

    assigns = assign(assigns, :form, to_form(%{"group_answer" => group?}, as: :breakout))

    ~H"""
    <div class="flex flex-col gap-1 rounded-lg border border-line p-3">
      <ClaperWeb.Component.Checkbox.checkbox
        form={@form}
        key={:group_answer}
        label={gettext("Group answer")}
      />
      <p class="text-sm text-muted">
        {gettext(
          "Ticked: the group answers once, written by a note-taker the group picks. Unticked: each person answers."
        )}
      </p>
    </div>
    """
  end

  @doc """
  On an intro page, a form's "Show answers on the big screen" switch
  (decision 15). Its value comes back as `params["intro"]`.
  """
  attr :piece_target, :any, required: true

  def big_screen_choice(%{piece_target: {target, _}} = assigns)
      when target in [:intro_new, :intro_edit] do
    show? =
      case assigns.piece_target do
        {:intro_edit, %{data: data}} -> data["show_answers"] == true
        _ -> false
      end

    assigns = assign(assigns, :form, to_form(%{"show_answers" => show?}, as: :intro))

    ~H"""
    <div class="flex flex-col gap-1 rounded-lg border border-line p-3">
      <ClaperWeb.Component.Checkbox.checkbox
        form={@form}
        key={:show_answers}
        label={gettext("Show answers on the big screen")}
      />
      <p class="text-sm text-muted">
        {gettext(
          "Ticked: what people write appears on the big screen, without names. Unticked: only how many people answered."
        )}
      </p>
    </div>
    """
  end

  def big_screen_choice(assigns) do
    ~H"""
    """
  end

  @doc "The blank content each editor starts from (the same as on a slide)."
  def blank("poll"),
    do: %Claper.Polls.Poll{
      poll_opts: [
        %Claper.Polls.PollOpt{content: gettext("Yes")},
        %Claper.Polls.PollOpt{content: gettext("No")}
      ]
    }

  def blank("quiz"),
    do: %Claper.Quizzes.Quiz{
      quiz_questions: [
        %Claper.Quizzes.QuizQuestion{
          id: 0,
          quiz_question_opts: [
            %Claper.Quizzes.QuizQuestionOpt{id: 0},
            %Claper.Quizzes.QuizQuestionOpt{id: 1}
          ]
        }
      ]
    }

  def blank("form"),
    do: %Claper.Forms.Form{
      fields: [%Claper.Forms.Field{name: gettext("Your thoughts"), type: "text"}]
    }

  def blank("word_cloud"), do: %Claper.WordClouds.WordCloud{}
  def blank("embed"), do: %Claper.Embeds.Embed{}

  @doc """
  Saves the editor's params into the piece and goes back to the builder.
  `schema` is the editor's own schema: content errors come back as its
  changeset and show in the form as usual. `breakout_params` carries the
  "Group answer" checkbox (nil for pieces nobody answers); on an intro page, the form's
  "Show answers on the big screen" switch.
  """
  def save(socket, kind, schema, params, breakout_params \\ nil)

  # An interaction on an intro page (docs/INTRO.md): saved, then everyone
  # showing the page (builder preview, phones) is told.
  def save(%{assigns: %{piece_target: {target, owner}}} = socket, kind, schema, params, extra)
      when target in [:intro_new, :intro_edit] do
    data = if is_map(extra), do: Map.take(extra, ["show_answers"]), else: nil

    result =
      case target do
        :intro_new -> Claper.Intro.add_interaction(owner, kind, params, data || %{})
        :intro_edit -> Claper.Intro.update_interaction(owner, params, data)
      end

    case result do
      {:ok, _} ->
        page_id = if target == :intro_new, do: owner.id, else: owner.intro_page_id
        Claper.Intro.broadcast_changed(Claper.Repo.get!(Claper.Intro.Page, page_id))
        {:noreply, push_navigate(socket, to: socket.assigns.return_to)}

      {:error, %Ecto.Changeset{data: %^schema{}} = changeset} ->
        {:noreply, assign(socket, :changeset, changeset)}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, gettext("Could not save this"))}
    end
  end

  def save(socket, kind, schema, params, breakout_params) do
    settings = piece_settings(breakout_params)

    result =
      case socket.assigns.piece_target do
        {:new, packet} ->
          Breakouts.add_piece(packet, Map.put(settings, :kind, kind), params)

        {:edit, piece} when settings == %{} ->
          Breakouts.update_content(piece, params)

        {:edit, piece} ->
          Breakouts.update_piece_and_content(piece, settings, params)
      end

    case result do
      {:ok, _} ->
        {:noreply, push_navigate(socket, to: socket.assigns.return_to)}

      {:error, %Ecto.Changeset{data: %^schema{}} = changeset} ->
        {:noreply, assign(socket, :changeset, changeset)}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, gettext("Could not save this piece"))}
    end
  end

  defp piece_settings(%{"group_answer" => "true"}), do: %{answer_scope: "group"}

  defp piece_settings(%{"group_answer" => _}),
    do: %{answer_scope: "individual"}

  defp piece_settings(_), do: %{}
end
