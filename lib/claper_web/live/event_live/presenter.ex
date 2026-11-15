defmodule ClaperWeb.EventLive.Presenter do
  use ClaperWeb, :live_view

  alias ClaperWeb.Presence
  alias Claper.Embeds.Embed
  alias Claper.Polls.Poll
  alias Claper.Forms.Form
  alias Claper.Quizzes.Quiz
  alias Claper.WordClouds.WordCloud
  alias Claper.Presentations
  alias Claper.Transcriptions

  # Replies shown under a message on the big screen (the latest ones).
  @replies_shown 3

  @impl true
  def mount(%{"code" => code} = params, session, socket) do
    with %{"locale" => locale} <- session do
      Gettext.put_locale(ClaperWeb.Gettext, locale)
    end

    event =
      Claper.Events.get_event_with_code(code, [
        :user,
        presentation_file: [:polls, :presentation_state]
      ])

    if is_nil(event) || not leader?(socket, event) do
      {:ok,
       socket
       |> put_flash(:error, gettext("Event doesn't exist"))
       |> redirect(to: "/")}
    else
      if connected?(socket) do
        Claper.Events.Event.subscribe(event.uuid)
        Claper.Presentations.subscribe(event.presentation_file.id)
        Claper.Events.record_event_activity(event)
      end

      endpoint_config = Application.get_env(:claper, ClaperWeb.Endpoint)[:url]
      port = endpoint_config[:port]
      scheme = endpoint_config[:scheme]
      host = endpoint_config[:host]
      path = endpoint_config[:path]

      default_ports = [80, 443]
      port_suffix = if port in default_ports, do: "", else: ":" <> Integer.to_string(port)

      host = "#{scheme}://#{host}#{port_suffix}/#{path}"

      transcription_config =
        Transcriptions.get_transcription_config(event.presentation_file.id)

      socket =
        socket
        |> assign(:attendees_nb, Presence.attendee_count(event.uuid))
        |> assign(
          :host,
          host
        )
        |> assign(:event, event)
        |> assign(:iframe, !is_nil(params["iframe"]))
        |> assign(:state, event.presentation_file.presentation_state)
        |> assign_intro_results(event)
        |> assign(:posts, list_posts(socket, event.uuid))
        |> assign(:pinned_posts, list_pinned_posts(socket, event.uuid))
        |> assign(:show_only_pinned, event.presentation_file.presentation_state.show_only_pinned)
        |> assign(:reacts, [])
        |> assign(:transcription_text, "")
        |> assign(:transcription_config, transcription_config)
        |> poll_at_position
        |> form_at_position
        |> embed_at_position
        |> quiz_at_position
        |> word_cloud_at_position
        |> load_breakout()

      {:ok, socket, temporary_assigns: []}
    end
  end

  defp load_breakout(socket) do
    screen =
      case Claper.Breakouts.open_run_for_presentation(socket.assigns.event.presentation_file.id) do
        nil ->
          nil

        run ->
          %{
            run: run,
            breakout: run.breakout,
            groups: length(run.groups),
            people: Enum.sum(Enum.map(run.groups, &length(&1.members))),
            report: ClaperWeb.BreakoutLive.ViewData.report(run)
          }
      end

    assign(socket, :breakout_screen, screen)
  end

  defp update_post_in_list(posts, updated_post) do
    Enum.map(posts, fn post ->
      if post.id == updated_post.id, do: updated_post, else: post
    end)
  end

  # One message on the big screen, in the full list and the pinned list
  # alike: its name, text, the latest replies and the reactions.
  attr :post, :map, required: true
  attr :iframe, :boolean, default: false

  defp presenter_post(assigns) do
    assigns =
      assign(assigns,
        shown_replies: Enum.take(assigns.post.replies, -@replies_shown),
        earlier_replies: max(length(assigns.post.replies) - @replies_shown, 0)
      )

    ~H"""
    <div class={if @post.__meta__.state == :deleted, do: "hidden"} id={"#{@post.id}-post"}>
      <div class="px-4 pb-2 pt-3 rounded-b-lg rounded-tr-lg bg-base-200 shadow-md text-base-content break-word mt-4">
        <p
          :if={@post.name}
          class={"#{if @iframe, do: "text-base", else: "text-lg"} text-muted font-semibold mb-2 mr-2"}
        >
          {@post.name}
        </p>
        <p class={"#{if @iframe, do: "text-xl", else: "text-3xl"}"}>{@post.body}</p>

        <%!-- Replies, as on phones (a line down the left, name over text), up
             to the latest three so one thread cannot fill the screen
             (Jose, 2026-11-14) --%>
        <div
          :if={@post.replies != []}
          class={["flex flex-col", if(@iframe, do: "mt-2 gap-1.5", else: "mt-4 gap-3")]}
        >
          <p
            :if={@earlier_replies > 0}
            class={["font-semibold text-muted", if(@iframe, do: "text-xs", else: "text-base")]}
          >
            {ngettext("1 earlier reply", "%{count} earlier replies", @earlier_replies)}
          </p>
          <div
            :for={reply <- @shown_replies}
            id={"presenter-reply-#{reply.uuid}"}
            class={["border-l-2 border-primary", if(@iframe, do: "pl-2", else: "pl-4")]}
          >
            <p class={["font-semibold text-muted", if(@iframe, do: "text-xs", else: "text-base")]}>
              {ClaperWeb.EventLive.PostComponent.reply_author_name(reply)}
            </p>
            <p class={if(@iframe, do: "text-base", else: "text-2xl")}>{reply.body}</p>
          </div>
        </div>

        <div
          :if={@post.like_count > 0 || @post.love_count > 0 || @post.lol_count > 0}
          class="flex h-6 space-x-2 text-lg text-muted pb-3 items-center mt-5"
        >
          <div :if={@post.like_count > 0} class="flex items-center">
            <img src="/images/icons/thumb.svg" class={"#{if @iframe, do: "h-4", else: "h-7"}"} />
            <span class="ml-1">{@post.like_count}</span>
          </div>
          <div :if={@post.love_count > 0} class="flex items-center">
            <img src="/images/icons/heart.svg" class={"#{if @iframe, do: "h-4", else: "h-7"}"} />
            <span class="ml-1">{@post.love_count}</span>
          </div>
          <div :if={@post.lol_count > 0} class="flex items-center">
            <img src="/images/icons/laugh.svg" class={"#{if @iframe, do: "h-4", else: "h-7"}"} />
            <span class="ml-1">{@post.lol_count}</span>
          </div>
        </div>
      </div>
    </div>
    """
  end

  defp leader?(%{assigns: %{current_user: current_user}} = _socket, event),
    do: Claper.Events.can_manage?(current_user, event)

  defp leader?(_socket, _event), do: false

  @impl true
  def handle_info(%{event: "presence_diff"}, %{assigns: %{event: event}} = socket) do
    # Kept in the assigns too, so a counter drawn later (the big screen's
    # badge switched on) starts from the real number.
    count = Presence.attendee_count(event.uuid)

    {:noreply,
     socket |> assign(:attendees_nb, count) |> push_event("update-attendees", %{count: count})}
  end

  @impl true
  def handle_info({:post_created, post}, socket) do
    {:noreply,
     socket
     |> update(:posts, fn posts -> posts ++ [post] end)}
  end

  @impl true
  def handle_info({:post_pinned, post}, socket) do
    {:noreply,
     socket
     |> update(:pinned_posts, fn pinned_posts -> pinned_posts ++ [post] end)}
  end

  @impl true
  def handle_info({:post_unpinned, post}, socket) do
    {:noreply,
     socket
     |> update(:pinned_posts, fn pinned_posts ->
       Enum.reject(pinned_posts, fn p -> p.id == post.id end)
     end)}
  end

  @impl true
  def handle_info({:state_updated, state}, socket) do
    {:noreply,
     socket
     |> assign(:state, state)
     |> push_event("page", %{current_page: state.position})
     |> push_event("reset-global-react", %{})
     |> poll_at_position
     |> embed_at_position
     |> word_cloud_at_position}
  end

  @impl true
  def handle_info({:post_updated, updated_post}, socket) do
    updated_posts = update_post_in_list(socket.assigns.posts, updated_post)
    updated_pinned_posts = update_post_in_list(socket.assigns.pinned_posts, updated_post)

    {:noreply,
     socket
     |> assign(:posts, updated_posts)
     |> assign(:pinned_posts, updated_pinned_posts)}
  end

  @impl true
  def handle_info({:post_deleted, post}, socket) do
    updated_posts = Enum.reject(socket.assigns.posts, fn p -> p.id == post.id end)
    updated_pinned_posts = Enum.reject(socket.assigns.pinned_posts, fn p -> p.id == post.id end)

    {:noreply,
     socket |> assign(:posts, updated_posts) |> assign(:pinned_posts, updated_pinned_posts)}
  end

  @impl true
  def handle_info({:poll_updated, poll}, socket) do
    if poll.enabled do
      {:noreply,
       socket
       |> update(:current_poll, fn _current_poll -> poll end)}
    else
      {:noreply,
       socket
       |> update(:current_poll, fn _current_poll -> nil end)}
    end
  end

  @impl true
  def handle_info({:poll_deleted, _poll}, socket) do
    {:noreply,
     socket
     |> update(:current_poll, fn _current_poll -> nil end)}
  end

  @impl true
  def handle_info({:form_updated, form}, socket) do
    if form.enabled do
      {:noreply,
       socket
       |> assign_form(form)}
    else
      {:noreply,
       socket
       |> update(:current_form, fn _current_form -> nil end)}
    end
  end

  @impl true
  def handle_info({event, %Claper.Forms.FormSubmit{form_id: form_id}}, socket)
      when event in [:form_submit_created, :form_submit_updated, :form_submit_deleted] do
    case socket.assigns.current_form do
      %Form{id: ^form_id} = form -> {:noreply, assign_form(socket, form)}
      _ -> {:noreply, socket}
    end
  end

  @impl true
  def handle_info({:form_deleted, _form}, socket) do
    {:noreply,
     socket
     |> update(:current_form, fn _current_form -> nil end)}
  end

  @impl true
  def handle_info({:embed_updated, embed}, socket) do
    if embed.enabled do
      {:noreply,
       socket
       |> update(:current_embed, fn _current_embed -> embed end)}
    else
      {:noreply,
       socket
       |> update(:current_embed, fn _current_embed -> nil end)}
    end
  end

  @impl true
  def handle_info({:embed_deleted, _embed}, socket) do
    {:noreply,
     socket
     |> update(:current_embed, fn _current_embed -> nil end)}
  end

  @impl true
  def handle_info({:quiz_updated, quiz}, socket) do
    {:noreply,
     socket
     |> update(:current_quiz, fn _current_quiz -> quiz end)}
  end

  @impl true
  def handle_info({:quiz_deleted, _quiz}, socket) do
    {:noreply,
     socket
     |> update(:current_quiz, fn _current_quiz -> nil end)}
  end

  # The message may be about another cloud, or carry a struct read before a word
  # was hidden, so the projected cloud is read again for the current slide.
  @impl true
  def handle_info({:word_cloud_updated, _word_cloud}, socket) do
    {:noreply, word_cloud_at_position(socket)}
  end

  @impl true
  def handle_info({:word_cloud_deleted, _word_cloud}, socket) do
    {:noreply, word_cloud_at_position(socket)}
  end

  @impl true
  def handle_info(
        {:word_cloud_entry_added, %WordCloud{id: id}},
        %{assigns: %{current_word_cloud: %WordCloud{id: id}}} = socket
      ) do
    {:noreply, word_cloud_at_position(socket)}
  end

  @impl true
  def handle_info({:chat_visible, value}, socket) do
    {:noreply,
     socket
     |> push_event("chat-visible", %{value: value})
     |> update(:chat_visible, fn _chat_visible -> value end)}
  end

  @impl true
  def handle_info({:show_only_pinned, value}, socket) do
    {:noreply,
     socket
     |> push_event("show_only_pinned", %{value: value})
     |> update(:show_only_pinned, fn _show_only_pinned -> value end)}
  end

  @impl true
  def handle_info({:poll_visible, value}, socket) do
    {:noreply,
     socket
     |> push_event("poll-visible", %{value: value})
     |> update(:poll_visible, fn _poll_visible -> value end)}
  end

  @impl true
  def handle_info({:join_screen_visible, value}, socket) do
    {:noreply,
     socket
     |> push_event("join-screen-visible", %{value: value})
     |> update(:join_screen_visible, fn _join_screen_visible -> value end)}
  end

  @impl true
  def handle_info({:react, type}, socket) do
    {:noreply,
     socket
     |> push_event("global-react", %{type: type})}
  end

  @impl true
  def handle_info(
        {:current_interaction, %Poll{} = interaction},
        socket
      ) do
    {:noreply,
     socket
     |> assign(:current_poll, interaction)
     |> assign(:current_embed, nil)
     |> assign(:current_form, nil)
     |> assign(:current_quiz, nil)
     |> assign(:current_word_cloud, nil)}
  end

  @impl true
  def handle_info(
        {:current_interaction, %Embed{} = interaction},
        socket
      ) do
    {:noreply,
     socket
     |> assign(:current_embed, interaction)
     |> assign(:current_poll, nil)
     |> assign(:current_form, nil)
     |> assign(:current_quiz, nil)
     |> assign(:current_word_cloud, nil)}
  end

  @impl true
  def handle_info(
        {:current_interaction, %Form{} = interaction},
        socket
      ) do
    {:noreply,
     socket
     |> assign_form(interaction)
     |> assign(:current_poll, nil)
     |> assign(:current_embed, nil)
     |> assign(:current_quiz, nil)
     |> assign(:current_word_cloud, nil)}
  end

  @impl true
  def handle_info(
        {:current_interaction, %Quiz{} = interaction},
        socket
      ) do
    {:noreply,
     socket
     |> assign(:current_quiz, interaction)
     |> assign(:current_poll, nil)
     |> assign(:current_embed, nil)
     |> assign(:current_form, nil)
     |> assign(:current_word_cloud, nil)}
  end

  @impl true
  def handle_info(
        {:current_interaction, %WordCloud{}},
        socket
      ) do
    {:noreply,
     socket
     |> word_cloud_at_position()
     |> assign(:current_poll, nil)
     |> assign(:current_embed, nil)
     |> assign(:current_form, nil)
     |> assign(:current_quiz, nil)}
  end

  @impl true
  def handle_info(
        {:current_interaction, nil},
        socket
      ) do
    {:noreply,
     socket
     |> assign(:current_poll, nil)
     |> assign(:current_embed, nil)
     |> assign(:current_form, nil)
     |> assign(:current_quiz, nil)
     |> assign(:current_word_cloud, nil)}
  end

  @impl true
  def handle_info(
        {:review_quiz_questions},
        socket
      ) do
    send_update(
      ClaperWeb.EventLive.ManageableQuizComponent,
      id: "#{socket.assigns.current_quiz.id}-quiz",
      current_question_idx: 0
    )

    {:noreply, socket |> assign(:current_question_idx, 0)}
  end

  @impl true
  def handle_info(
        {:next_quiz_question},
        socket
      ) do
    idx =
      if socket.assigns.current_question_idx <
           length(socket.assigns.current_quiz.quiz_questions) - 1,
         do: socket.assigns.current_question_idx + 1,
         else: -1

    send_update(
      ClaperWeb.EventLive.ManageableQuizComponent,
      id: "#{socket.assigns.current_quiz.id}-quiz",
      current_question_idx: idx
    )

    {:noreply, socket |> assign(:current_question_idx, idx)}
  end

  @impl true
  def handle_info(
        {:prev_quiz_question},
        socket
      ) do
    idx =
      if socket.assigns.current_question_idx > 0,
        do: socket.assigns.current_question_idx - 1,
        else: 0

    send_update(
      ClaperWeb.EventLive.ManageableQuizComponent,
      id: "#{socket.assigns.current_quiz.id}-quiz",
      current_question_idx: idx
    )

    {:noreply, socket |> assign(:current_question_idx, idx)}
  end

  @impl true
  def handle_info({:transcription_created, transcription}, socket) do
    {:noreply, socket |> assign(:transcription_text, transcription.text)}
  end

  @impl true
  def handle_info({:transcription_delta, text}, socket) do
    {:noreply, socket |> assign(:transcription_text, text)}
  end

  @impl true
  def handle_info({:transcription_config_updated, config}, socket) do
    {:noreply, socket |> assign(:transcription_config, config)}
  end

  @impl true
  def handle_info({:transcription_config_deleted, _config}, socket) do
    {:noreply, socket |> assign(:transcription_config, nil)}
  end

  @impl true
  # Breakouts (docs/BREAKOUT.md): the big screen follows the breakout under way.
  def handle_info({:breakout, :changed, _run_id}, socket), do: {:noreply, load_breakout(socket)}

  # People joining late change the count; answers matter only for the group on screen.
  def handle_info({:breakout, :group, _run_id, _group_id}, socket),
    do: {:noreply, load_breakout(socket)}

  def handle_info({:breakout, :answer, _run_id, group_id}, socket) do
    case socket.assigns[:breakout_screen] do
      %{report: %{result: %{group: %{id: ^group_id}}}} -> {:noreply, load_breakout(socket)}
      _ -> {:noreply, socket}
    end
  end

  # The intro page's interactions: answers came in, or the page changed
  # (docs/INTRO.md, step 9).
  def handle_info(message, socket) when message in [:intro_answered, :intro_updated],
    do: {:noreply, assign_intro_results(socket, socket.assigns.event)}

  def handle_info(_, socket) do
    {:noreply, socket}
  end

  # Live results of the intro page's interactions, shown beside the join
  # screen before the start (decisions 13-15).
  defp assign_intro_results(socket, event) do
    page = Claper.Intro.ensure_event_page(event)
    assign(socket, :intro_results, Claper.Intro.results(page))
  end

  @impl true
  def handle_params(params, _url, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :show, _params) do
    socket
  end

  defp poll_at_position(%{assigns: %{event: event, state: state}} = socket) do
    with poll <-
           Claper.Polls.get_poll_current_position(
             event.presentation_file.id,
             state.position
           ) do
      socket |> assign(:current_poll, poll)
    end
  end

  # The current slide form and, for the big screen, what people wrote in it
  # (shown while "Show answers on big screen" is on).
  defp assign_form(socket, nil), do: assign(socket, current_form: nil, form_summary: nil)

  defp assign_form(socket, %Form{} = form),
    do: assign(socket, current_form: form, form_summary: Claper.Forms.summarize_answers(form))

  defp form_at_position(%{assigns: %{event: event, state: state}} = socket) do
    with form <-
           Claper.Forms.get_form_current_position(
             event.presentation_file.id,
             state.position
           ) do
      socket |> assign_form(form)
    end
  end

  defp embed_at_position(%{assigns: %{event: event, state: state}} = socket) do
    with embed <-
           Claper.Embeds.get_embed_current_position(
             event.presentation_file.id,
             state.position
           ) do
      socket |> assign(:current_embed, embed)
    end
  end

  defp quiz_at_position(%{assigns: %{event: event, state: state}} = socket) do
    with quiz <-
           Claper.Quizzes.get_quiz_current_position(
             event.presentation_file.id,
             state.position
           ) do
      socket |> assign(:current_quiz, quiz) |> assign(:current_question_idx, 0)
    end
  end

  defp word_cloud_at_position(%{assigns: %{event: event, state: state}} = socket) do
    word_cloud =
      Claper.WordClouds.get_word_cloud_current_position(
        event.presentation_file.id,
        state.position
      )

    assign_word_cloud(socket, word_cloud)
  end

  defp assign_word_cloud(socket, %WordCloud{} = word_cloud) do
    socket
    |> assign(:current_word_cloud, word_cloud)
    |> assign(:word_cloud_words, Claper.WordClouds.list_words(word_cloud))
  end

  defp assign_word_cloud(socket, nil) do
    socket
    |> assign(:current_word_cloud, nil)
    |> assign(:word_cloud_words, [])
  end

  defp list_posts(_socket, event_id) do
    Claper.Posts.list_posts(event_id, [:event, :reactions])
  end

  defp list_pinned_posts(_socket, event_id) do
    Claper.Posts.list_pinned_posts(event_id, [:event, :reactions])
  end
end
