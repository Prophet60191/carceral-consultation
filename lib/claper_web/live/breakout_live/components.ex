defmodule ClaperWeb.BreakoutLive.Components do
  @moduledoc """
  Shared Breakout screen parts (docs/BREAKOUT.md, steps 4–5):

    * `group_chip/1`, `group_banner/1` — a group's number on its color
      (theme roles `group-1`…`group-6`, repeating from group 7)
    * `group_heading/1` — a group's chip: the one label every screen puts
      above a group's answers
    * `group_report/1` — a group's answers, unlabelled
    * `countdown/1` — the timer (`BreakoutCountdown` hook; signal only)
    * `phone_screen/1` — a person's group screen: one task at a time with
      a progress bar, Back and Next, the note-taker request on group answers
    * `outside_screen/1` — for people who open the app after the groups
      were made (groups are locked at the start, decision 24)
    * `piece_input/1` — a piece on a phone, by kind (reading, answering, or
      read-only when the group's note-taker answers)
    * `results/1` — a piece's answers summed up, by kind (the presenter's
      group cards and reporting back)

  This is the web side of the piece contract (`Claper.Breakouts.PieceType`):
  a new piece type adds a clause to `piece_input/1` and `results/1`.
  """
  use Phoenix.Component
  use Gettext, backend: ClaperWeb.Gettext

  # Written out in full so Tailwind finds every class.
  @group_classes %{
    1 => "bg-group-1 text-group-content",
    2 => "bg-group-2 text-group-content",
    3 => "bg-group-3 text-group-content",
    4 => "bg-group-4 text-group-content",
    5 => "bg-group-5 text-group-content",
    6 => "bg-group-6 text-group-content"
  }
  @group_bars %{
    1 => "bg-group-1",
    2 => "bg-group-2",
    3 => "bg-group-3",
    4 => "bg-group-4",
    5 => "bg-group-5",
    6 => "bg-group-6"
  }

  @doc "The color classes for a group number (group 7 starts the colors again)."
  def group_class(number), do: Map.fetch!(@group_classes, rem(number - 1, 6) + 1)
  def group_bar(number), do: Map.fetch!(@group_bars, rem(number - 1, 6) + 1)

  attr :number, :integer, required: true
  attr :class, :string, default: nil

  def group_chip(assigns) do
    ~H"""
    <span class={[
      "inline-flex items-center rounded-full px-2.5 py-0.5 text-sm font-bold",
      group_class(@number),
      @class
    ]}>
      {gettext("Group %{n}", n: @number)}
    </span>
    """
  end

  attr :number, :integer, required: true
  attr :subtitle, :string, default: nil

  def group_banner(assigns) do
    ~H"""
    <div class={["rounded-xl px-4 py-4 text-center", group_class(@number)]}>
      <p class="text-3xl font-extrabold leading-tight">{gettext("Group %{n}", n: @number)}</p>
      <p :if={@subtitle} class="mt-1 text-sm font-medium">{@subtitle}</p>
    </div>
    """
  end

  attr :ends_at, :any, required: true
  attr :id, :string, required: true
  attr :class, :string, default: nil

  def countdown(assigns) do
    ~H"""
    <span
      :if={@ends_at}
      id={@id}
      phx-hook="BreakoutCountdown"
      data-ends-at={DateTime.to_iso8601(@ends_at)}
      data-times-up={gettext("Time's up")}
      class={["inline-flex items-center gap-1.5 tabular-nums", @class]}
    >
      <svg
        class="size-4"
        viewBox="0 0 24 24"
        fill="none"
        stroke="currentColor"
        stroke-width="1.5"
        aria-hidden="true"
      >
        <path
          stroke-linecap="round"
          stroke-linejoin="round"
          d="M12 6v6h4.5m4.5 0a9 9 0 1 1-18 0 9 9 0 0 1 18 0Z"
        />
      </svg>
      <span data-countdown-text></span>
    </span>
    """
  end

  ## A piece on a phone

  attr :piece, :map, required: true
  attr :content, :any, required: true
  attr :response, :map, default: nil, doc: "the answer shown: own, or the group's"
  attr :editable, :boolean, default: true
  attr :mates, :list, default: [], doc: "group-mates' responses, when the piece shares them"

  attr :events, :string,
    default: "bk",
    doc: "prefix of the events taps send: bk (breakout phones) or intro (the intro page)"

  def piece_input(%{piece: %{kind: "text"}} = assigns) do
    ~H"""
    <div class="whitespace-pre-line text-base leading-relaxed text-base-content">{@piece.body}</div>
    """
  end

  def piece_input(%{piece: %{kind: "embed"}} = assigns) do
    ~H"""
    <div class="h-72 overflow-hidden rounded-lg bg-stage">
      <.live_component
        id={"bk-embed-#{@piece.id}"}
        module={ClaperWeb.EventLive.EmbedIframeComponent}
        provider={@content.provider}
        content={@content.content}
        title={@content.title}
      />
    </div>
    """
  end

  def piece_input(%{piece: %{kind: "poll"}} = assigns) do
    assigns = assign(assigns, :chosen, (assigns.response || %{}) |> Map.get("options", []))

    ~H"""
    <div class="flex flex-col gap-2">
      <p class="font-semibold text-base-content">{@content.title}</p>
      <p :if={@content.multiple} class="text-sm text-muted">{gettext("Choose one or more")}</p>
      <button
        :for={opt <- @content.poll_opts}
        type="button"
        class="choice text-left"
        aria-pressed={to_string(opt.id in @chosen)}
        disabled={!@editable}
        phx-click={"#{@events}_poll"}
        phx-value-piece={@piece.id}
        phx-value-opt={opt.id}
      >
        {opt.content}
      </button>
      <.mates_summary :if={@mates != []} piece={@piece} content={@content} mates={@mates} />
    </div>
    """
  end

  def piece_input(%{piece: %{kind: "quiz"}} = assigns) do
    assigns = assign(assigns, :answers, (assigns.response || %{}) |> Map.get("answers", %{}))

    ~H"""
    <div class="flex flex-col gap-4">
      <p class="font-semibold text-base-content">{@content.title}</p>
      <div :for={q <- @content.quiz_questions} class="flex flex-col gap-2">
        <p class="text-base-content">{q.content}</p>
        <button
          :for={opt <- q.quiz_question_opts}
          type="button"
          class="choice text-left"
          aria-pressed={to_string(opt.id in Map.get(@answers, to_string(q.id), []))}
          disabled={!@editable}
          phx-click={"#{@events}_quiz"}
          phx-value-piece={@piece.id}
          phx-value-question={q.id}
          phx-value-opt={opt.id}
        >
          {opt.content}
        </button>
      </div>
      <.mates_summary :if={@mates != []} piece={@piece} content={@content} mates={@mates} />
    </div>
    """
  end

  def piece_input(%{piece: %{kind: "form"}} = assigns) do
    assigns = assign(assigns, :fields, (assigns.response || %{}) |> Map.get("fields", %{}))

    ~H"""
    <div class="flex flex-col gap-3">
      <p class="font-semibold text-base-content">{@content.title}</p>
      <form
        id={"bk-form-#{@piece.id}"}
        phx-change={"#{@events}_form"}
        phx-submit={"#{@events}_form"}
        class="flex flex-col gap-3"
      >
        <input type="hidden" name="piece" value={@piece.id} />
        <label :for={field <- @content.fields} class="flex flex-col gap-1">
          <span class="text-sm font-bold text-base-content">{field.name}</span>
          <textarea
            name={"fields[#{field.name}]"}
            rows="3"
            class="textarea"
            readonly={!@editable}
            phx-debounce="800"
          >{Map.get(@fields, field.name)}</textarea>
        </label>
        <p :if={@editable} class="text-sm text-muted">{gettext("Saves as you type.")}</p>
      </form>
      <.mates_summary :if={@mates != []} piece={@piece} content={@content} mates={@mates} />
    </div>
    """
  end

  def piece_input(%{piece: %{kind: "word_cloud"}} = assigns) do
    assigns = assign(assigns, :words, (assigns.response || %{}) |> Map.get("words", []))

    ~H"""
    <div class="flex flex-col gap-3">
      <p class="font-semibold text-base-content">{@content.title}</p>
      <div :if={@words != []} class="flex flex-wrap gap-2">
        <span :for={word <- @words} class="badge badge-soft gap-1">
          {word}
          <button
            :if={@editable}
            type="button"
            class="btn btn-ghost btn-xs btn-square"
            phx-click={"#{@events}_word_remove"}
            phx-value-piece={@piece.id}
            phx-value-word={word}
            aria-label={gettext("Remove %{word}", word: word)}
          >
            &times;
          </button>
        </span>
      </div>
      <form
        :if={@editable and length(@words) < @content.max_entries}
        id={"bk-words-#{@piece.id}"}
        phx-submit={"#{@events}_word_add"}
        class="flex gap-2"
      >
        <input type="hidden" name="piece" value={@piece.id} />
        <input
          type="text"
          name="word"
          maxlength="60"
          autocomplete="off"
          class="input flex-1"
          placeholder={gettext("Add a word")}
        />
        <button type="submit" class="btn btn-primary">{gettext("Add")}</button>
      </form>
      <p class="text-sm text-muted">
        {gettext("Up to %{n} words", n: @content.max_entries)}
      </p>
      <.mates_summary :if={@mates != []} piece={@piece} content={@content} mates={@mates} />
    </div>
    """
  end

  attr :piece, :map, required: true
  attr :content, :any, required: true
  attr :mates, :list, required: true

  defp mates_summary(assigns) do
    module = Claper.Breakouts.PieceType.module_for!(assigns.piece)
    assigns = assign(assigns, :summary, module.summarize(assigns.content, assigns.mates))

    ~H"""
    <div class="mt-2 rounded-lg border border-line p-3">
      <p class="mb-2 text-sm font-bold text-base-content">{gettext("Your group's answers")}</p>
      <.results piece={@piece} content={@content} summary={@summary} />
    </div>
    """
  end

  ## Answers summed up

  attr :piece, :map, required: true
  attr :content, :any, required: true
  attr :summary, :map, required: true
  attr :large, :boolean, default: false

  def results(%{piece: %{kind: kind}} = assigns) when kind in ["text", "embed"] do
    ~H"""
    """
  end

  def results(%{summary: summary} = assigns) when map_size(summary) == 0 do
    ~H"""
    """
  end

  def results(%{piece: %{kind: "poll"}} = assigns) do
    ~H"""
    <div class="flex flex-col gap-2">
      <div :for={opt <- @summary.options} class="flex flex-col gap-1">
        <div class={["flex justify-between gap-3", @large && "text-lg", !@large && "text-sm"]}>
          <span class="text-base-content">{opt.content}</span>
          <span class="tabular-nums text-muted">{opt.count}</span>
        </div>
        <div class="h-1.5 overflow-hidden rounded-full bg-base-300">
          <div
            class="h-full rounded-full bg-chart-1"
            style={"width: #{percent(opt.count, @summary.total)}%"}
          >
          </div>
        </div>
      </div>
      <p :if={@summary.total == 0} class="text-sm text-muted">{gettext("No answers yet")}</p>
    </div>
    """
  end

  def results(%{piece: %{kind: "quiz"}} = assigns) do
    ~H"""
    <div class="flex flex-col gap-3">
      <div :for={q <- @summary.questions} class="flex flex-col gap-1">
        <p class={["text-base-content", @large && "text-lg", !@large && "text-sm"]}>{q.content}</p>
        <p class="text-sm text-muted">
          {gettext("%{correct} of %{answered} right", correct: q.correct, answered: q.answered)}
        </p>
        <ul class="flex flex-col gap-0.5">
          <li :for={o <- q.options} class="flex justify-between gap-3 text-sm">
            <span class={[
              o.is_correct && "font-semibold text-success",
              !o.is_correct && "text-base-content"
            ]}>
              {o.content}{if o.is_correct, do: " ✓"}
            </span>
            <span class="tabular-nums text-muted">{o.count}</span>
          </li>
        </ul>
      </div>
    </div>
    """
  end

  def results(%{piece: %{kind: "form"}} = assigns) do
    ~H"""
    <div class="flex flex-col gap-3">
      <div :for={f <- @summary.fields} class="flex flex-col gap-1">
        <p class={["font-bold text-base-content", @large && "text-xl", !@large && "text-sm"]}>
          {f.name}
        </p>
        <p :if={f.answers == []} class="text-sm text-muted">{gettext("No answers yet")}</p>
        <%!-- Line breaks people typed are kept (whitespace-pre-line), so the
             answer must sit right against its tags: phx-no-format keeps the
             formatter from adding a line break before it. --%>
        <p
          :for={a <- f.answers}
          class={[
            "whitespace-pre-line rounded-md bg-base-300 px-3 py-2 text-base-content",
            @large && "text-lg",
            !@large && "text-sm"
          ]}
          phx-no-format
        >{a}</p>
      </div>
    </div>
    """
  end

  def results(%{piece: %{kind: "word_cloud"}} = assigns) do
    ~H"""
    <div class="flex flex-wrap gap-2">
      <span :for={w <- @summary.words} class={["badge badge-soft", @large && "badge-lg"]}>
        {w.text}<span :if={w.count > 1} class="tabular-nums">&nbsp;×{w.count}</span>
      </span>
      <p :if={@summary.words == []} class="text-sm text-muted">{gettext("No words yet")}</p>
    </div>
    """
  end

  def results(assigns) do
    ~H"""
    """
  end

  defp percent(_count, 0), do: 0
  defp percent(count, total), do: round(count * 100 / total)

  ## The phone screen while a breakout runs

  attr :state, :map, required: true, doc: "ClaperWeb.BreakoutLive.ViewData.phone/2"
  attr :message, :string, default: nil
  attr :error, :string, default: nil

  def phone_screen(assigns) do
    ~H"""
    <div
      id="breakout-phone"
      class="fixed inset-0 z-40 overflow-y-auto bg-base-100 font-display text-base-content"
    >
      <div class="mx-auto flex w-full max-w-lg flex-col gap-4 px-4 pb-16 pt-4">
        <.group_banner
          number={@state.group.number}
          subtitle={ngettext("1 person", "%{count} people", @state.size)}
        />

        <div class="flex flex-wrap items-center justify-between gap-2 text-sm text-muted">
          <span>{@state.breakout.title}</span>
          <.countdown
            id="bk-phone-timer"
            ends_at={@state.run.ends_at}
            class="countdown-alert rounded-full bg-base-300 px-3 py-1 font-semibold text-base-content data-[state=ending]:bg-error data-[state=ending]:text-error-content data-[state=up]:bg-error data-[state=up]:text-error-content"
          />
        </div>

        <div :if={@message} role="status" class="panel border-info">
          <div class="flex items-start gap-3 p-3">
            <p class="flex-1 text-base-content">
              <span class="font-bold">{gettext("From the presenter:")}</span> {@message}
            </p>
            <button
              type="button"
              class="btn btn-ghost btn-sm btn-square"
              phx-click="bk_dismiss_message"
              aria-label={gettext("Dismiss")}
            >
              &times;
            </button>
          </div>
        </div>

        <%!-- Reporting back: the group on the big screen --%>
        <div :if={@state.report} class="flex flex-col gap-3">
          <p class="text-sm font-bold uppercase tracking-wide text-muted">
            {gettext("Reporting back")}
          </p>
          <.group_heading number={@state.report.result.group.number} />
          <.group_report result={@state.report.result} contents={@state.report.contents} />
          <p class="text-sm text-muted">{gettext("Your group's work is saved.")}</p>
        </div>

        <div :if={!@state.report} class="flex flex-col gap-4">
          <%!-- One task at a time (decision 23) --%>
          <div :if={@state.total > 1} id="bk-progress" class="flex flex-col gap-2">
            <p :if={@state.step == 0} class="text-base-content">
              {gettext(
                "This breakout has %{count} tasks. Work through them in order; you can go back to change an answer.",
                count: @state.total
              )}
            </p>
            <p class="text-sm font-semibold text-base-content">
              {if @state.step < @state.total,
                do: gettext("Task %{n} of %{total}", n: @state.step + 1, total: @state.total),
                else: gettext("All %{total} tasks done", total: @state.total)}
            </p>
            <div
              class="h-2 overflow-hidden rounded-full bg-line"
              role="progressbar"
              aria-valuemin="0"
              aria-valuemax={@state.total}
              aria-valuenow={@state.step}
              aria-label={gettext("Tasks done")}
            >
              <div
                class="h-full rounded-full bg-primary transition-[width]"
                style={"width: #{percent(@state.step, @state.total)}%"}
              >
              </div>
            </div>
          </div>

          <p :if={@error} role="alert" class="text-sm text-error">{@error}</p>

          <%!-- The task they are on --%>
          <.phone_task
            :for={{piece, i} <- Enum.with_index(@state.pieces)}
            :if={i == @state.step}
            piece={piece}
            index={i}
            state={@state}
          />

          <div :if={@state.total > 0 and @state.step == @state.total} class="panel">
            <div class="flex flex-col gap-2 p-4">
              <p class="font-semibold">{gettext("You've finished every task.")}</p>
              <p class="text-sm text-muted">
                {gettext(
                  "You can go back to check or change your answers until the presenter stops the breakout."
                )}
              </p>
            </div>
          </div>

          <div :if={@state.total > 1} class="flex items-center justify-between gap-3">
            <button
              type="button"
              class="btn btn-outline"
              phx-click="bk_back"
              disabled={@state.step == 0}
            >
              {gettext("Back")}
            </button>
            <button
              :if={@state.step < @state.total}
              type="button"
              class="btn btn-primary"
              phx-click="bk_next"
            >
              {next_label(@state)}
            </button>
          </div>

          <p :if={@state.pieces == []} class="text-center text-muted">
            {gettext("Your group has nothing to work on yet.")}
          </p>
        </div>
      </div>
    </div>
    """
  end

  defp next_label(%{step: step, total: total}) when step == total - 1, do: gettext("Finish")

  defp next_label(%{step: step, pieces: pieces}) do
    if Claper.Breakouts.PieceType.module_for!(Enum.at(pieces, step)).answerable?(),
      do: gettext("Next"),
      else: gettext("Done reading")
  end

  # One task on the phone. A group answer carries its own note-taker request
  # (decision 22): it is the only place a note-taker is asked for.
  attr :piece, :map, required: true
  attr :index, :integer, required: true
  attr :state, :map, required: true

  defp phone_task(assigns) do
    piece = assigns.piece
    state = assigns.state
    group? = piece.answer_scope == "group"

    assigns =
      assign(assigns,
        module: Claper.Breakouts.PieceType.module_for!(piece),
        group?: group?,
        response: if(group?, do: state.group_answers[piece.id], else: state.own[piece.id])
      )

    ~H"""
    <section id={"bk-piece-#{@piece.id}"} class="panel">
      <div class="panel-header gap-2">
        <span class="text-sm font-semibold text-muted">{@index + 1}. {@module.label()}</span>
        <span :if={@module.answerable?()} class="ml-auto text-sm text-muted">
          <%= cond do %>
            <% @group? -> %>
              {gettext("Group answer")}
            <% @response -> %>
              {gettext("Answered")}
            <% true -> %>
              {gettext("Your answer")}
          <% end %>
        </span>
      </div>

      <div
        :if={@group?}
        id={"bk-note-taker-#{@piece.id}"}
        class="flex flex-wrap items-center gap-3 border-b border-line bg-base-300 p-3"
      >
        <%= cond do %>
          <% @state.note_taker? -> %>
            <p class="flex-1 text-sm font-semibold">
              {gettext("You're writing this answer for Group %{n}.", n: @state.group.number)}
            </p>
            <button type="button" class="btn btn-outline btn-sm" phx-click="bk_hand_off">
              {gettext("Hand off")}
            </button>
          <% @state.has_note_taker? -> %>
            <p class="flex-1 text-sm text-muted">
              {if @response,
                do: gettext("Your note-taker's answer for the group:"),
                else: gettext("Your note-taker writes this answer for the group.")}
            </p>
          <% true -> %>
            <p class="flex-1 text-sm">
              {gettext("This one is a group answer. Someone needs to take notes.")}
            </p>
            <button type="button" class="btn btn-primary btn-sm" phx-click="bk_claim">
              {gettext("I'll take notes")}
            </button>
        <% end %>
      </div>

      <div class="p-3">
        <.piece_input
          piece={@piece}
          content={@state.contents[@piece.id]}
          response={@response}
          editable={not @group? or @state.note_taker?}
          mates={if @piece.visible_to_group, do: Map.get(@state.mates, @piece.id, []), else: []}
        />
      </div>
    </section>
    """
  end

  ## Opened during a breakout, without a group

  attr :breakout, :map, required: true

  def outside_screen(assigns) do
    ~H"""
    <div
      id="breakout-outside"
      class="fixed inset-0 z-40 flex items-center justify-center overflow-y-auto bg-base-100 px-4 font-display text-base-content"
    >
      <div class="flex max-w-sm flex-col items-center gap-3 text-center">
        <p class="text-sm text-muted">{@breakout.title}</p>
        <p class="text-2xl font-bold">{gettext("Groups are working.")}</p>
        <p class="text-lg">{gettext("See the presenter to be assigned to a group.")}</p>
      </div>
    </div>
    """
  end

  ## A group's heading: its chip

  attr :number, :integer, required: true
  attr :large, :boolean, default: false
  slot :inner_block, doc: "optional details shown at the right end of the line"

  def group_heading(assigns) do
    ~H"""
    <div class="flex flex-wrap items-center gap-3">
      <.group_chip number={@number} class={@large && "text-xl px-4 py-1"} />
      <span :if={@inner_block != []} class="ml-auto text-sm text-base-content">
        {render_slot(@inner_block)}
      </span>
    </div>
    """
  end

  ## One group's answers (the surrounding screen names the group)

  attr :result, :map, required: true, doc: "one entry of Claper.Breakouts.results/1"
  attr :contents, :map, required: true
  attr :large, :boolean, default: false

  def group_report(assigns) do
    ~H"""
    <div class="flex flex-col gap-4">
      <div
        :for={%{piece: piece, summary: summary} <- @result.pieces}
        :if={Claper.Breakouts.PieceType.module_for!(piece).answerable?()}
        class="panel"
      >
        <div class="flex flex-col gap-3 p-3">
          <p class={["font-semibold text-base-content", @large && "text-xl"]}>
            {(@contents[piece.id] && @contents[piece.id].title) || ""}
          </p>
          <.results piece={piece} content={@contents[piece.id]} summary={summary} large={@large} />
        </div>
      </div>
    </div>
    """
  end
end
