defmodule ClaperWeb.EventLive.Manage do
  use ClaperWeb, :live_view

  alias Claper.{Embeds, Events, Forms, Polls, Presentations, Quizzes, Transcriptions, WordClouds}
  alias Claper.Transcriptions.TranscriptionConfig
  alias Claper.Workers.PresentationThumbnails
  alias ClaperWeb.Presence

  @event_preload [
    :user,
    :lti_resource,
    presentation_file: [:polls, :presentation_state]
  ]

  @impl true
  def mount(%{"code" => code}, session, socket) do
    with %{"locale" => locale} <- session do
      Gettext.put_locale(ClaperWeb.Gettext, locale)
    end

    event = Events.get_event_with_code(code, @event_preload)

    if is_nil(event) || not leader?(socket, event) do
      {:ok,
       socket
       |> put_flash(:error, gettext("Event doesn't exist"))
       |> redirect(to: "/")}
    else
      socket
      |> assign(:security_audit_ip, ClaperWeb.SecurityAudit.client_ip(session))
      |> mount_event(event)
    end
  end

  defp mount_event(socket, event) do
    if connected?(socket) do
      Claper.Events.Event.subscribe(event.uuid)
      Presentations.subscribe(event.presentation_file.id)
      Events.subscribe_user_events(socket.assigns.current_user.id)
      Claper.Materials.subscribe(event)
      Events.record_event_activity(event)
    end

    posts = list_all_posts(socket, event.uuid)
    pinned_posts = list_pinned_posts(socket, event.uuid)
    questions = list_all_questions(socket, event.uuid)
    form_submits = list_form_submits(socket, event.presentation_file.id)

    audio_token =
      Phoenix.Token.sign(ClaperWeb.Endpoint, "audio_token", %{
        user_id: socket.assigns.current_user.id,
        event_uuid: event.uuid
      })

    transcription_config =
      Transcriptions.get_transcription_config(event.presentation_file.id)

    transcription_globally_enabled = Claper.Settings.transcription_globally_enabled?()

    # Auto-start transcription worker if config says enabled and globally enabled
    if connected?(socket) && transcription_globally_enabled && transcription_config &&
         transcription_config.enabled do
      unless Claper.Transcriptions.TranscriptionWorker.running?(event.uuid) do
        DynamicSupervisor.start_child(
          Claper.TranscriptionSupervisor,
          {Claper.Transcriptions.TranscriptionWorker, {event.uuid, event.presentation_file.id}}
        )
      end
    end

    socket =
      socket
      |> assign(:interaction_modal, false)
      |> assign(:settings_modal, false)
      |> assign(:reorder, nil)
      |> assign(:attendees_nb, Presence.attendee_count(event.uuid))
      |> assign(:event, event)
      |> assign(:sort_questions_by, "date")
      |> assign(:state, event.presentation_file.presentation_state)
      |> assign(:audio_token, audio_token)
      |> assign(:transcription_config, transcription_config)
      |> assign(:transcription_globally_enabled, transcription_globally_enabled)
      |> stream(:posts, posts)
      |> stream(:questions, questions)
      |> stream(:pinned_posts, pinned_posts)
      |> stream(:form_submits, form_submits)
      |> assign(:pinned_post_count, length(pinned_posts))
      |> assign(:question_count, length(questions))
      |> assign(:post_count, length(posts))
      |> assign(
        :total_interactions,
        Claper.Interactions.get_number_total_interactions(event.presentation_file.id)
      )
      |> assign(
        :form_submit_count,
        length(form_submits)
      )
      |> assign(:create, nil)
      |> assign(:list_tab, :posts)
      |> assign(:create_action, :new)
      |> assign(
        :missing_slide_thumbnails,
        Presentations.missing_slide_thumbnails?(event.presentation_file)
      )
      |> assign(:thumbnail_cache_bust, thumbnail_cache_bust())
      |> assign(:thumbnail_regeneration_in_progress, false)
      |> push_event("page-manage", %{
        current_page: event.presentation_file.presentation_state.position,
        timeout: 500
      })
      |> then(fn s ->
        if transcription_config && transcription_config.enabled do
          push_event(s, "transcription-state", %{enabled: true})
        else
          s
        end
      end)
      |> interactions_at_position(event.presentation_file.presentation_state.position)

    {:ok, socket}
  end

  defp leader?(%{assigns: %{current_user: current_user}} = _socket, event),
    do: Claper.Events.can_manage?(current_user, event)

  defp leader?(_socket, _event), do: false

  defp event_id(%{assigns: %{event: event}}), do: event.id

  defp get_interaction_for_event("poll", id, socket),
    do: Polls.get_poll_for_event(id, event_id(socket))

  defp get_interaction_for_event("breakout", id, socket),
    do:
      Claper.Breakouts.get_breakout_for_presentation(
        id,
        socket.assigns.event.presentation_file.id
      )

  defp get_interaction_for_event("form", id, socket),
    do: Forms.get_form_for_event(id, event_id(socket))

  defp get_interaction_for_event("embed", id, socket),
    do: Embeds.get_embed_for_event(id, event_id(socket))

  defp get_interaction_for_event("quiz", id, socket),
    do: Quizzes.get_quiz_for_event(id, event_id(socket))

  defp get_interaction_for_event("word_cloud", id, socket),
    do: WordClouds.get_word_cloud_for_event(id, event_id(socket))

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
    socket =
      socket
      |> stream_insert(:posts, post, at: 0)
      |> update(:post_count, fn post_count -> post_count + 1 end)

    case ClaperWeb.Helpers.body_without_links(post.body) =~ "?" do
      true ->
        {:noreply,
         socket
         |> stream_insert(:questions, post, at: 0)
         |> update(:question_count, fn question_count -> question_count + 1 end)
         |> push_event("scroll", %{})}

      _ ->
        {:noreply, socket |> push_event("scroll", %{})}
    end
  end

  @impl true
  def handle_info({:post_updated, updated_post}, socket) do
    {:noreply,
     socket
     |> stream_insert(:posts, updated_post)
     |> then(fn socket ->
       sorted_questions =
         list_all_questions(socket, socket.assigns.event.uuid, socket.assigns.sort_questions_by)

       stream(socket, :questions, sorted_questions, reset: true)
     end)
     |> then(fn socket ->
       if updated_post.pinned do
         stream_insert(socket, :pinned_posts, updated_post)
       else
         stream_delete(socket, :pinned_posts, updated_post)
       end
     end)}
  end

  @impl true
  def handle_info({:post_deleted, deleted_post}, socket) do
    socket =
      socket
      |> stream_delete(:posts, deleted_post)
      |> stream_delete(:pinned_posts, deleted_post)
      |> update(:pinned_post_count, fn pinned_post_count ->
        pinned_post_count - if deleted_post.pinned, do: 1, else: 0
      end)
      |> update(:post_count, fn post_count -> post_count - 1 end)

    case ClaperWeb.Helpers.body_without_links(deleted_post.body) =~ "?" do
      true ->
        {:noreply,
         socket
         |> stream_delete(:questions, deleted_post)
         |> update(:question_count, fn question_count -> question_count - 1 end)}

      _ ->
        {:noreply, socket}
    end
  end

  @impl true
  def handle_info({:post_pinned, post}, socket) do
    updated_socket =
      socket
      |> stream_insert(:posts, post)
      |> stream_insert(:pinned_posts, post, at: 0)
      |> stream_insert(:questions, post)
      |> assign(:pinned_post_count, socket.assigns.pinned_post_count + 1)

    {:noreply, updated_socket}
  end

  @impl true
  def handle_info({:post_unpinned, post}, socket) do
    updated_socket =
      socket
      |> stream_insert(:posts, post)
      |> stream_delete(:pinned_posts, post)
      |> stream_insert(:questions, post)
      |> assign(:pinned_post_count, socket.assigns.pinned_post_count - 1)

    {:noreply, updated_socket}
  end

  @impl true
  def handle_info({:form_submit_created, fs}, socket) do
    {:noreply,
     socket
     |> stream_insert(:form_submits, fs)
     |> update(:form_submit_count, fn form_submit_count -> form_submit_count + 1 end)
     |> push_event("scroll", %{})}
  end

  @impl true
  def handle_info({:form_submit_updated, fs}, socket) do
    {:noreply, socket |> stream_insert(:form_submits, fs)}
  end

  @impl true
  def handle_info({:form_submit_deleted, fs}, socket) do
    {:noreply,
     socket
     |> stream_delete(:form_submits, fs)
     |> update(:form_submit_count, fn form_submit_count -> form_submit_count - 1 end)}
  end

  @impl true
  def handle_info({:poll_created, poll}, socket) do
    {:noreply,
     socket
     |> interactions_at_position(poll.position)}
  end

  @impl true
  def handle_info({:form_created, form}, socket) do
    {:noreply,
     socket
     |> interactions_at_position(form.position)}
  end

  @impl true
  def handle_info({:embed_created, embed}, socket) do
    {:noreply,
     socket
     |> interactions_at_position(embed.position)}
  end

  @impl true
  def handle_info({:quiz_created, quiz}, socket) do
    {:noreply,
     socket
     |> interactions_at_position(quiz.position)}
  end

  @impl true
  def handle_info({:word_cloud_created, word_cloud}, socket) do
    {:noreply,
     socket
     |> interactions_at_position(word_cloud.position)}
  end

  @impl true
  def handle_info({:poll_updated, _poll}, socket) do
    {:noreply,
     socket
     |> interactions_at_position(socket.assigns.state.position)}
  end

  @impl true
  def handle_info({:embed_updated, _embed}, socket) do
    {:noreply,
     socket
     |> interactions_at_position(socket.assigns.state.position)}
  end

  @impl true
  def handle_info({:form_updated, _form}, socket) do
    {:noreply,
     socket
     |> interactions_at_position(socket.assigns.state.position)}
  end

  @impl true
  def handle_info({:quiz_updated, _quiz}, socket) do
    {:noreply,
     socket
     |> interactions_at_position(socket.assigns.state.position)}
  end

  @impl true
  def handle_info({:word_cloud_updated, _word_cloud}, socket) do
    {:noreply,
     socket
     |> interactions_at_position(socket.assigns.state.position)}
  end

  # Fired for every word an attendee sends, so only the preview is refreshed
  # instead of the whole interaction list.
  @impl true
  def handle_info(
        {:word_cloud_entry_added, %{id: id}},
        %{assigns: %{current_interaction: %WordClouds.WordCloud{id: id}}} = socket
      ) do
    words =
      case WordClouds.get_word_cloud_for_event(id, event_id(socket)) do
        nil -> []
        word_cloud -> WordClouds.list_words(word_cloud)
      end

    {:noreply, assign(socket, :word_cloud_words, words)}
  end

  @impl true
  def handle_info({:poll_deleted, poll}, socket) do
    {:noreply,
     socket
     |> interactions_at_position(poll.position)}
  end

  @impl true
  def handle_info({:embed_deleted, embed}, socket) do
    {:noreply,
     socket
     |> interactions_at_position(embed.position)}
  end

  @impl true
  def handle_info({:form_deleted, form}, socket) do
    {:noreply,
     socket
     |> interactions_at_position(form.position)}
  end

  @impl true
  def handle_info({:quiz_deleted, quiz}, socket) do
    {:noreply,
     socket
     |> interactions_at_position(quiz.position)}
  end

  @impl true
  def handle_info({:word_cloud_deleted, word_cloud}, socket) do
    {:noreply,
     socket
     |> interactions_at_position(word_cloud.position)}
  end

  @impl true
  def handle_info(
        {:current_interaction, interaction},
        socket
      ) do
    if socket.assigns.current_interaction != interaction do
      position = if interaction, do: interaction.position, else: socket.assigns.state.position

      {:noreply,
       socket
       |> assign(:current_interaction, interaction)
       |> interactions_at_position(position)}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_info({:state_updated, state}, socket) do
    if state.position != socket.assigns.state.position do
      {:noreply, socket |> assign(:state, state) |> interactions_at_position(state.position)}
    else
      {:noreply, socket |> assign(:state, state)}
    end
  end

  @impl true
  def handle_info(
        {:presentation_file_process_done, %{id: presentation_file_id}},
        %{assigns: %{event: %{presentation_file: %{id: presentation_file_id}}}} = socket
      ) do
    {:noreply, refresh_event(socket)}
  end

  @impl true
  def handle_info(
        {:presentation_file_thumbnails_regenerated, presentation_file_id},
        %{assigns: %{event: %{presentation_file: %{id: presentation_file_id}}}} = socket
      ) do
    {:noreply,
     socket
     |> refresh_event()
     |> assign(:thumbnail_regeneration_in_progress, false)
     |> put_flash(:info, gettext("Thumbnails regenerated successfully"))}
  end

  @impl true
  def handle_info(
        {:presentation_file_thumbnail_regeneration_failed, presentation_file_id},
        %{assigns: %{event: %{presentation_file: %{id: presentation_file_id}}}} = socket
      ) do
    {:noreply,
     socket
     |> assign(:thumbnail_regeneration_in_progress, false)
     |> put_flash(:error, gettext("Could not regenerate thumbnails"))}
  end

  @impl true
  def handle_info({:transcription_config_created, config}, socket) do
    {:noreply, socket |> assign(:transcription_config, config)}
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
  def handle_info({:transcription_delta, _text}, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_info({:transcription_created, _transcription}, socket) do
    {:noreply, socket}
  end

  @impl true
  # A breakout started or stopped: its row shows Start or Live.
  def handle_info({:breakout, :changed, _run_id}, socket),
    do: {:noreply, socket |> interactions_at_position(socket.assigns.state.position)}

  # Materials changed (here, or by another facilitator): both Materials
  # cards (sidebar, settings window) reload.
  def handle_info(:open_materials_add, socket) do
    send_update(ClaperWeb.EventLive.MaterialsAddComponent, id: "materials-add", open: true)
    {:noreply, socket}
  end

  def handle_info(:materials_changed, socket) do
    for id <- ["settings-pane-materials", "settings-modal-pane-materials"] do
      send_update(ClaperWeb.EventLive.MaterialsComponent, id: id, refresh: true)
    end

    {:noreply, socket}
  end

  def handle_info(_, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_event(
        "current-page",
        %{"page" => page},
        %{assigns: %{state: state}} = socket
      ) do
    page = String.to_integer(page)

    {:ok, new_state} =
      Claper.Presentations.update_presentation_state(
        state,
        %{
          :position => page
        }
      )

    Phoenix.PubSub.broadcast(
      Claper.PubSub,
      "event:#{socket.assigns.event.uuid}",
      {:page_changed, page}
    )

    {:noreply,
     socket
     |> assign(:state, new_state)
     |> interactions_at_position(page)}
  end

  @impl true
  def handle_event(
        "reorder-slides",
        %{"from" => from, "to" => to},
        %{assigns: %{event: event, state: state}} = socket
      )
      when is_integer(from) and is_integer(to) and from != to do
    case Presentations.reorder_slides(event.presentation_file, from, to) do
      {:ok, _presentation_file, new_state} ->
        if new_state && new_state.position != state.position do
          Phoenix.PubSub.broadcast(
            Claper.PubSub,
            "event:#{event.uuid}",
            {:page_changed, new_state.position}
          )
        end

        socket = refresh_event(socket)

        {:noreply, socket |> interactions_at_position(socket.assigns.state.position)}

      {:error, _reason} ->
        {:noreply, socket |> put_flash(:error, gettext("Could not reorder slides"))}
    end
  end

  @impl true
  def handle_event(
        "move-interaction",
        %{"id" => id, "type" => type, "to" => to},
        %{assigns: %{event: event, state: state}} = socket
      )
      when is_integer(id) and is_integer(to) and
             type in ["poll", "form", "embed", "quiz", "word_cloud", "breakout"] do
    with interaction when not is_nil(interaction) <- get_interaction_for_event(type, id, socket),
         {:ok, _moved} <- Claper.Interactions.move_interaction(event, interaction, to) do
      if interaction.enabled do
        Phoenix.PubSub.broadcast(
          Claper.PubSub,
          "event:#{event.uuid}",
          {:current_interaction, nil}
        )
      end

      {:noreply, socket |> interactions_at_position(state.position)}
    else
      nil ->
        {:noreply, socket}

      {:error, _reason} ->
        {:noreply, socket |> put_flash(:error, gettext("Could not move interaction"))}
    end
  end

  @impl true
  def handle_event(
        "regenerate-thumbnails",
        _params,
        %{assigns: %{missing_slide_thumbnails: false}} = socket
      ) do
    {:noreply, socket}
  end

  @impl true
  def handle_event(
        "regenerate-thumbnails",
        _params,
        %{assigns: %{thumbnail_regeneration_in_progress: true}} = socket
      ) do
    {:noreply, socket}
  end

  @impl true
  def handle_event("regenerate-thumbnails", _params, socket) do
    presentation_file_id = socket.assigns.event.presentation_file.id
    user_id = socket.assigns.current_user.id

    case PresentationThumbnails.create(presentation_file_id, user_id) |> Oban.insert() do
      {:ok, _job} ->
        {:noreply,
         socket
         |> assign(:thumbnail_regeneration_in_progress, true)
         |> put_flash(:info, gettext("Thumbnail regeneration started"))}

      {:error, _changeset} ->
        {:noreply, socket |> put_flash(:error, gettext("Could not start thumbnail regeneration"))}
    end
  end

  def handle_event("poll-set-active", %{"id" => id}, socket) do
    case Polls.get_poll_for_event(id, event_id(socket)) do
      nil ->
        {:noreply, socket}

      poll ->
        activate(socket, poll)
    end
  end

  def handle_event("form-set-active", %{"id" => id}, socket) do
    case Forms.get_form_for_event(id, event_id(socket)) do
      nil ->
        {:noreply, socket}

      form ->
        activate(socket, form)
    end
  end

  def handle_event("embed-set-active", %{"id" => id}, socket) do
    case Embeds.get_embed_for_event(id, event_id(socket)) do
      nil ->
        {:noreply, socket}

      embed ->
        activate(socket, embed)
    end
  end

  def handle_event("word-cloud-set-active", %{"id" => id}, socket) do
    case WordClouds.get_word_cloud_for_event(id, event_id(socket)) do
      nil ->
        {:noreply, socket}

      word_cloud ->
        activate(socket, word_cloud)
    end
  end

  def handle_event("poll-set-inactive", %{"id" => id}, socket) do
    case Polls.get_poll_for_event(id, event_id(socket)) do
      nil ->
        {:noreply, socket}

      poll ->
        with {:ok, _} <- Claper.Interactions.disable_interaction(poll) do
          Phoenix.PubSub.broadcast(
            Claper.PubSub,
            "event:#{socket.assigns.event.uuid}",
            {:current_interaction, nil}
          )
        end

        {:noreply,
         socket
         |> assign(:current_interaction, nil)
         |> interactions_at_position(socket.assigns.state.position)}
    end
  end

  def handle_event("form-set-inactive", %{"id" => id}, socket) do
    case Forms.get_form_for_event(id, event_id(socket)) do
      nil ->
        {:noreply, socket}

      form ->
        with {:ok, _} <- Claper.Interactions.disable_interaction(form) do
          Phoenix.PubSub.broadcast(
            Claper.PubSub,
            "event:#{socket.assigns.event.uuid}",
            {:current_interaction, nil}
          )
        end

        {:noreply,
         socket
         |> assign(:current_interaction, nil)
         |> interactions_at_position(socket.assigns.state.position)}
    end
  end

  def handle_event("embed-set-inactive", %{"id" => id}, socket) do
    case Embeds.get_embed_for_event(id, event_id(socket)) do
      nil ->
        {:noreply, socket}

      embed ->
        with {:ok, _} <- Claper.Interactions.disable_interaction(embed) do
          Phoenix.PubSub.broadcast(
            Claper.PubSub,
            "event:#{socket.assigns.event.uuid}",
            {:current_interaction, nil}
          )
        end

        {:noreply,
         socket
         |> assign(:current_interaction, nil)
         |> interactions_at_position(socket.assigns.state.position)}
    end
  end

  def handle_event("word-cloud-set-inactive", %{"id" => id}, socket) do
    case WordClouds.get_word_cloud_for_event(id, event_id(socket)) do
      nil ->
        {:noreply, socket}

      word_cloud ->
        with {:ok, _} <- Claper.Interactions.disable_interaction(word_cloud) do
          Phoenix.PubSub.broadcast(
            Claper.PubSub,
            "event:#{socket.assigns.event.uuid}",
            {:current_interaction, nil}
          )
        end

        {:noreply,
         socket
         |> assign(:current_interaction, nil)
         |> interactions_at_position(socket.assigns.state.position)}
    end
  end

  @impl true
  def handle_event("quiz-set-active", %{"id" => id}, socket) do
    case Quizzes.get_quiz_for_event(id, event_id(socket), [
           :quiz_questions,
           quiz_questions: :quiz_question_opts
         ]) do
      nil ->
        {:noreply, socket}

      quiz ->
        activate(socket, quiz)
    end
  end

  def handle_event("quiz-set-inactive", %{"id" => id}, socket) do
    case Quizzes.get_quiz_for_event(id, event_id(socket)) do
      nil ->
        {:noreply, socket}

      quiz ->
        with {:ok, _} <- Claper.Interactions.disable_interaction(quiz) do
          Phoenix.PubSub.broadcast(
            Claper.PubSub,
            "event:#{socket.assigns.event.uuid}",
            {:current_interaction, nil}
          )
        end

        {:noreply,
         socket
         |> assign(:current_interaction, nil)
         |> interactions_at_position(socket.assigns.state.position)}
    end
  end

  @impl true
  def handle_event(
        "ban",
        %{"attendee_identifier" => attendee_identifier},
        %{assigns: %{event: event}} = socket
      ) do
    Claper.Posts.delete_all_posts(:attendee_identifier, attendee_identifier, event)

    ban(attendee_identifier, socket)
  end

  @impl true
  def handle_event("pin", %{"id" => id}, socket) do
    case Claper.Posts.get_post_for_event(id, event_id(socket), [:event]) do
      nil -> {:noreply, socket}
      post -> pin(post, socket)
    end
  end

  @impl true
  def handle_event("reply", %{"id" => id, "reply_body" => reply_body}, socket) do
    case String.trim(reply_body) do
      "" ->
        {:noreply, socket |> put_flash(:error, gettext("A reply cannot be empty"))}

      trimmed_body ->
        reply(id, trimmed_body, socket)
    end
  end

  @impl true
  def handle_event("delete-reply", %{"id" => id}, socket) do
    actor = {:user, socket.assigns.current_user, nil}

    case Claper.Posts.delete_post_reply(socket.assigns.event, id, actor) do
      {:ok, _reply} ->
        {:noreply, socket}

      {:error, :not_found} ->
        {:noreply, put_flash(socket, :error, gettext("Resource not found"))}

      {:error, :forbidden} ->
        {:noreply, put_flash(socket, :error, gettext("Resource not found"))}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, gettext("Could not delete reply"))}
    end
  end

  @impl true
  def handle_event(
        "ban",
        %{"user_id" => user_id},
        %{assigns: %{event: event}} = socket
      ) do
    Claper.Posts.delete_all_posts(:user_id, user_id, event)

    ban(String.to_integer(user_id), socket)
  end

  @impl true
  def handle_event(
        "checked",
        %{"key" => "chat_visible", "value" => value},
        %{assigns: %{state: state}} = socket
      ) do
    {:ok, new_state} =
      Claper.Presentations.update_presentation_state(
        state,
        %{
          :chat_visible => value
        }
      )

    {:noreply, socket |> assign(:state, new_state)}
  end

  @impl true
  def handle_event(
        "checked",
        %{"key" => "poll_visible", "value" => value},
        %{assigns: %{state: state}} = socket
      ) do
    {:ok, new_state} =
      Claper.Presentations.update_presentation_state(
        state,
        %{
          :poll_visible => value
        }
      )

    {:noreply, socket |> assign(:state, new_state)}
  end

  @impl true
  def handle_event(
        "checked",
        %{"key" => "chat_enabled", "value" => value},
        %{assigns: %{state: state}} = socket
      ) do
    {:ok, new_state} =
      Claper.Presentations.update_presentation_state(
        state,
        %{
          :chat_enabled => value
        }
      )

    {:noreply, socket |> assign(:state, new_state)}
  end

  @impl true
  def handle_event(
        "checked",
        %{"key" => "anonymous_chat_enabled", "value" => value},
        %{assigns: %{state: state}} = socket
      ) do
    {:ok, new_state} =
      Claper.Presentations.update_presentation_state(
        state,
        %{
          :anonymous_chat_enabled => value
        }
      )

    {:noreply, socket |> assign(:state, new_state)}
  end

  @impl true
  def handle_event(
        "checked",
        %{"key" => "message_reaction_enabled", "value" => value},
        %{assigns: %{state: state}} = socket
      ) do
    {:ok, new_state} =
      Claper.Presentations.update_presentation_state(
        state,
        %{
          :message_reaction_enabled => value
        }
      )

    {:noreply, socket |> assign(:state, new_state)}
  end

  @impl true
  def handle_event(
        "checked",
        %{"key" => "show_only_pinned", "value" => value},
        %{assigns: %{event: _event, state: state}} = socket
      ) do
    {:ok, new_state} =
      Claper.Presentations.update_presentation_state(
        state,
        %{
          :show_only_pinned => value
        }
      )

    {:noreply, socket |> assign(:state, new_state)}
  end

  @impl true
  def handle_event(
        "checked",
        %{"key" => "show_attendee_count", "value" => value},
        %{assigns: %{event: _event, state: state}} = socket
      ) do
    {:ok, new_state} =
      Claper.Presentations.update_presentation_state(
        state,
        %{
          :show_attendee_count => value
        }
      )

    {:noreply, socket |> assign(:state, new_state)}
  end

  @impl true
  def handle_event(
        "checked",
        %{"key" => "join_screen_visible", "value" => value},
        %{assigns: %{state: state}} = socket
      ) do
    {:ok, new_state} =
      Claper.Presentations.update_presentation_state(
        state,
        %{
          :join_screen_visible => value
        }
      )

    {:noreply, socket |> assign(:state, new_state)}
  end

  def handle_event("transcription-set-active", %{"id" => id}, socket) do
    if Claper.Settings.transcription_globally_enabled?() do
      case Transcriptions.get_transcription_config_for_event(id, event_id(socket)) do
        nil ->
          {:noreply, put_flash(socket, :error, gettext("Resource not found"))}

        config ->
          {:ok, config} = Transcriptions.set_transcription_enabled(config)
          event = socket.assigns.event

          DynamicSupervisor.start_child(
            Claper.TranscriptionSupervisor,
            {Claper.Transcriptions.TranscriptionWorker, {event.uuid, event.presentation_file.id}}
          )

          Phoenix.PubSub.broadcast(
            Claper.PubSub,
            "event:#{event.uuid}",
            {:transcription_config_updated, config}
          )

          {:noreply,
           socket
           |> assign(:transcription_config, config)
           |> push_event("transcription-state", %{enabled: true})}
      end
    else
      {:noreply,
       socket
       |> put_flash(:error, gettext("Transcription has been disabled by the administrator"))}
    end
  end

  def handle_event("transcription-set-inactive", %{"id" => id}, socket) do
    case Transcriptions.get_transcription_config_for_event(id, event_id(socket)) do
      nil ->
        {:noreply, put_flash(socket, :error, gettext("Resource not found"))}

      config ->
        {:ok, config} = Transcriptions.set_transcription_disabled(config)
        event = socket.assigns.event

        Claper.Transcriptions.TranscriptionWorker.stop(event.uuid)

        Phoenix.PubSub.broadcast(
          Claper.PubSub,
          "event:#{event.uuid}",
          {:transcription_config_updated, config}
        )

        {:noreply,
         socket
         |> assign(:transcription_config, config)
         |> push_event("transcription-state", %{enabled: false})}
    end
  end

  @impl true
  def handle_event(
        "checked",
        %{"key" => "quiz_show_results", "value" => value},
        %{assigns: %{current_interaction: interaction}} = socket
      ) do
    {:ok, new_interaction} =
      Claper.Quizzes.update_quiz(
        socket.assigns.event.uuid,
        interaction,
        %{
          :show_results => value
        }
      )

    {:noreply, socket |> assign(:current_interaction, new_interaction)}
  end

  @impl true
  def handle_event(
        "checked",
        %{"key" => "word_cloud_show_results", "value" => value},
        %{assigns: %{current_interaction: %WordClouds.WordCloud{} = word_cloud}} = socket
      ) do
    {:ok, word_cloud} =
      WordClouds.update_word_cloud(socket.assigns.event.uuid, word_cloud, %{show_results: value})

    {:noreply, socket |> assign(:current_interaction, word_cloud)}
  end

  # A toggle rendered before another moderator switched to a different
  # interaction.
  @impl true
  def handle_event("checked", %{"key" => "word_cloud_show_results"}, socket),
    do: {:noreply, socket}

  @impl true
  def handle_event("hide-word", %{"id" => id, "key" => key}, socket) do
    case WordClouds.get_word_cloud_for_event(id, event_id(socket)) do
      nil ->
        {:noreply, socket}

      word_cloud ->
        {:ok, _} = WordClouds.hide_word(socket.assigns.event.uuid, word_cloud, key)
        {:noreply, interactions_at_position(socket, socket.assigns.state.position)}
    end
  end

  @impl true
  def handle_event("unhide-word", %{"id" => id, "key" => key}, socket) do
    case WordClouds.get_word_cloud_for_event(id, event_id(socket)) do
      nil ->
        {:noreply, socket}

      word_cloud ->
        {:ok, _} = WordClouds.unhide_word(socket.assigns.event.uuid, word_cloud, key)
        {:noreply, interactions_at_position(socket, socket.assigns.state.position)}
    end
  end

  @impl true
  def handle_event("checked", %{"key" => "review_quiz_questions"}, socket) do
    Phoenix.PubSub.broadcast(
      Claper.PubSub,
      "event:#{socket.assigns.event.uuid}",
      {:review_quiz_questions}
    )

    {:noreply, socket}
  end

  @impl true
  def handle_event("checked", %{"key" => "next_quiz_question"}, socket) do
    Phoenix.PubSub.broadcast(
      Claper.PubSub,
      "event:#{socket.assigns.event.uuid}",
      {:next_quiz_question}
    )

    {:noreply, socket}
  end

  @impl true
  def handle_event("checked", %{"key" => "prev_quiz_question"}, socket) do
    Phoenix.PubSub.broadcast(
      Claper.PubSub,
      "event:#{socket.assigns.event.uuid}",
      {:prev_quiz_question}
    )

    {:noreply, socket}
  end

  @impl true
  def handle_event("delete", %{"id" => id}, socket) do
    case Claper.Posts.get_post_for_event(id, event_id(socket), [:event]) do
      nil ->
        {:noreply, socket}

      post ->
        {:ok, _} = Claper.Posts.delete_post(post)

        updated_socket =
          if post.pinned do
            stream(socket, :pinned_posts, list_pinned_posts(socket, socket.assigns.event.uuid),
              reset: true
            )

            stream(socket, :posts, list_all_posts(socket, socket.assigns.event.uuid), reset: true)
          else
            stream(socket, :posts, list_all_posts(socket, socket.assigns.event.uuid), reset: true)
          end

        {:noreply, updated_socket}
    end
  end

  @impl true
  def handle_event("sort-questions", %{"sort" => sort}, socket) do
    {:noreply,
     socket
     |> assign(:sort_questions_by, sort)
     |> stream(:questions, list_all_questions(socket, socket.assigns.event.uuid, sort),
       reset: true
     )}
  end

  @impl true
  def handle_event("delete-form-submit", %{"id" => id}, socket) do
    case Claper.Forms.get_form_submit_for_event(id, event_id(socket)) do
      nil ->
        {:noreply, socket}

      form_submit ->
        {:ok, _} = Claper.Forms.delete_form_submit(socket.assigns.event.uuid, form_submit)

        {:noreply,
         assign(
           socket,
           :form_submits,
           list_form_submits(socket, socket.assigns.event.presentation_file.id)
         )}
    end
  end

  @impl true
  def handle_event("list-tab", %{"tab" => tab}, socket) do
    {tab_atom, socket} =
      case tab do
        "posts" ->
          {:posts,
           stream(socket, :posts, list_all_posts(socket, socket.assigns.event.uuid), reset: true)}

        "questions" ->
          {:questions,
           stream(socket, :questions, list_all_questions(socket, socket.assigns.event.uuid),
             reset: true
           )}

        "forms" ->
          {:forms,
           stream(
             socket,
             :form_submits,
             list_form_submits(socket, socket.assigns.event.presentation_file.id),
             reset: true
           )}

        "pinned_posts" ->
          {:pinned_posts,
           stream(
             socket,
             :pinned_posts,
             list_pinned_posts(socket, socket.assigns.event.uuid),
             reset: true
           )}

        _ ->
          {:posts,
           stream(socket, :posts, list_all_posts(socket, socket.assigns.event.uuid), reset: true)}
      end

    {:noreply, assign(socket, :list_tab, tab_atom)}
  end

  @impl true
  def handle_event("maybe-redirect", _params, socket) do
    if socket.assigns.create != nil do
      {:noreply,
       socket
       |> push_navigate(to: ~p"/e/#{socket.assigns.event.code}/manage")}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("delete-poll", %{"id" => id}, socket) do
    case Polls.get_poll_for_event(id, event_id(socket)) do
      nil ->
        {:noreply, socket}

      poll ->
        {:ok, _} = Polls.delete_poll(socket.assigns.event.uuid, poll)
        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("delete-quiz", %{"id" => id}, socket) do
    case Quizzes.get_quiz_for_event(id, event_id(socket)) do
      nil ->
        {:noreply, socket}

      quiz ->
        {:ok, _} = Quizzes.delete_quiz(socket.assigns.event.uuid, quiz)
        {:noreply, socket}
    end
  end

  @impl true
  def handle_event(
        "toggle-interaction-modal",
        _params,
        %{assigns: %{interaction_modal: _interaction_modal = true}} = socket
      ) do
    {:noreply, socket |> push_navigate(to: ~p"/e/#{socket.assigns.event.code}/manage")}
  end

  @impl true
  def handle_event(
        "toggle-interaction-modal",
        _params,
        %{assigns: %{interaction_modal: _interaction_modal}} = socket
      ) do
    {:noreply, socket |> assign(:interaction_modal, true)}
  end

  @impl true
  # Start Event / Back to intro (docs/INTRO.md): moves every phone at once
  # (the presentation state is broadcast like any other setting).
  def handle_event(event, _params, %{assigns: %{state: state}} = socket)
      when event in ["start-event", "back-to-intro"] do
    {:ok, state} =
      Claper.Presentations.update_presentation_state(state, %{started: event == "start-event"})

    {:noreply,
     socket
     |> assign(:state, state)
     |> ClaperWeb.Toast.push(
       :success,
       if(state.started,
         do: gettext("Event started"),
         else: gettext("Phones show the intro page again")
       )
     )}
  end

  @impl true
  def handle_event("toggle-settings-modal", _params, socket) do
    {:noreply, update(socket, :settings_modal, &(!&1))}
  end

  # Reorder (Jose, 2026-11-14): a dialog listing this slide's interactions.
  # The new order lives in `:reorder` until Save; Cancel drops it.
  @impl true
  def handle_event("open-reorder", _params, %{assigns: %{interactions: interactions}} = socket)
      when length(interactions) > 1,
      do: {:noreply, assign(socket, :reorder, interactions)}

  def handle_event("open-reorder", _params, socket), do: {:noreply, socket}

  def handle_event("reorder-move", %{"index" => index, "dir" => dir}, socket)
      when dir in ["up", "down"] do
    with list when is_list(list) <- socket.assigns.reorder,
         {index, ""} <- Integer.parse(to_string(index)),
         target = if(dir == "up", do: index - 1, else: index + 1),
         true <- index in 0..(length(list) - 1) and target in 0..(length(list) - 1) do
      list =
        list
        |> List.replace_at(index, Enum.at(list, target))
        |> List.replace_at(target, Enum.at(list, index))

      {:noreply, assign(socket, :reorder, list)}
    else
      _ -> {:noreply, socket}
    end
  end

  def handle_event("reorder-cancel", _params, socket),
    do: {:noreply, assign(socket, :reorder, nil)}

  def handle_event(
        "reorder-save",
        _params,
        %{assigns: %{reorder: list, event: event, state: state}} = socket
      )
      when is_list(list) do
    keys = Enum.map(list, &{Claper.Interactions.type_key(&1), &1.id})

    case Claper.Interactions.reorder(event, state.position, keys) do
      {:ok, _interactions} ->
        {:noreply,
         socket
         |> assign(:reorder, nil)
         |> interactions_at_position(state.position)}

      {:error, :mismatch} ->
        {:noreply,
         socket
         |> interactions_at_position(state.position)
         |> then(&assign(&1, :reorder, &1.assigns.interactions))
         |> put_flash(
           :error,
           gettext("This slide's interactions changed meanwhile. Here is the current list.")
         )}
    end
  end

  def handle_event("reorder-save", _params, socket), do: {:noreply, socket}

  @impl true
  def handle_params(params, _url, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :show, _params) do
    socket
  end

  defp apply_action(socket, :add_poll, _params) do
    socket
    |> assign(:create, "poll")
    |> assign(:interaction_modal, true)
    |> assign(:create_action, :new)
    |> assign(:poll, %Polls.Poll{
      poll_opts: [%Polls.PollOpt{content: gettext("Yes")}, %Polls.PollOpt{content: gettext("No")}]
    })
  end

  defp apply_action(socket, :edit_poll, %{"id" => id}) do
    case Polls.get_poll_for_event(id, event_id(socket)) do
      nil ->
        socket
        |> put_flash(:error, gettext("Resource not found"))
        |> push_navigate(to: ~p"/e/#{socket.assigns.event.code}/manage")

      poll ->
        socket
        |> assign(:create, "poll")
        |> assign(:interaction_modal, true)
        |> assign(:create_action, :edit)
        |> assign(:poll, poll)
    end
  end

  defp apply_action(socket, :add_form, _params) do
    socket
    |> assign(:create, "form")
    |> assign(:interaction_modal, true)
    |> assign(:create_action, :new)
    |> assign(:form, %Forms.Form{
      fields: [
        %Forms.Field{name: gettext("Name"), type: "text"},
        %Forms.Field{name: gettext("Email"), type: "email"}
      ]
    })
  end

  defp apply_action(socket, :add_embed, _params) do
    socket
    |> assign(:create, "embed")
    |> assign(:interaction_modal, true)
    |> assign(:create_action, :new)
    |> assign(:embed, %Embeds.Embed{})
  end

  defp apply_action(socket, :import, _params) do
    socket
    |> assign(:create, "import")
    |> assign(:events, Claper.Events.list_events(socket.assigns.current_user.id))
  end

  defp apply_action(socket, :edit_form, %{"id" => id}) do
    case Forms.get_form_for_event(id, event_id(socket)) do
      nil ->
        socket
        |> put_flash(:error, gettext("Resource not found"))
        |> push_navigate(to: ~p"/e/#{socket.assigns.event.code}/manage")

      form ->
        socket
        |> assign(:create, "form")
        |> assign(:interaction_modal, true)
        |> assign(:create_action, :edit)
        |> assign(:form, form)
    end
  end

  defp apply_action(socket, :edit_embed, %{"id" => id}) do
    case Embeds.get_embed_for_event(id, event_id(socket)) do
      nil ->
        socket
        |> put_flash(:error, gettext("Resource not found"))
        |> push_navigate(to: ~p"/e/#{socket.assigns.event.code}/manage")

      embed ->
        socket
        |> assign(:create, "embed")
        |> assign(:interaction_modal, true)
        |> assign(:create_action, :edit)
        |> assign(:embed, embed)
    end
  end

  defp apply_action(socket, :add_quiz, _params) do
    socket
    |> assign(:create, "quiz")
    |> assign(:interaction_modal, true)
    |> assign(:create_action, :new)
    |> assign(:quiz, %Quizzes.Quiz{
      presentation_file_id: socket.assigns.event.presentation_file.id,
      quiz_questions: [
        %Quizzes.QuizQuestion{
          id: 0,
          quiz_question_opts: [
            %Quizzes.QuizQuestionOpt{
              id: 0
            },
            %Quizzes.QuizQuestionOpt{
              id: 1
            }
          ]
        }
      ]
    })
  end

  defp apply_action(socket, :edit_quiz, %{"id" => id}) do
    case Quizzes.get_quiz_for_event(id, event_id(socket), [
           :quiz_questions,
           quiz_questions: :quiz_question_opts
         ]) do
      nil ->
        socket
        |> put_flash(:error, gettext("Resource not found"))
        |> push_navigate(to: ~p"/e/#{socket.assigns.event.code}/manage")

      quiz ->
        socket
        |> assign(:create, "quiz")
        |> assign(:interaction_modal, true)
        |> assign(:create_action, :edit)
        |> assign(:quiz, quiz)
    end
  end

  defp apply_action(socket, :add_word_cloud, _params) do
    socket
    |> assign(:create, "word_cloud")
    |> assign(:interaction_modal, true)
    |> assign(:create_action, :new)
    |> assign(:word_cloud, %WordClouds.WordCloud{})
  end

  defp apply_action(socket, :edit_word_cloud, %{"id" => id}) do
    case WordClouds.get_word_cloud_for_event(id, event_id(socket)) do
      nil ->
        socket
        |> put_flash(:error, gettext("Resource not found"))
        |> push_navigate(to: ~p"/e/#{socket.assigns.event.code}/manage")

      word_cloud ->
        socket
        |> assign(:create, "word_cloud")
        |> assign(:interaction_modal, true)
        |> assign(:create_action, :edit)
        |> assign(:word_cloud, word_cloud)
    end
  end

  defp apply_action(socket, :add_transcription, _params) do
    existing = socket.assigns.transcription_config

    if existing do
      socket
      |> push_navigate(
        to: ~p"/e/#{socket.assigns.event.code}/manage/edit/transcription/#{existing.id}"
      )
    else
      socket
      |> assign(:create, "transcription")
      |> assign(:interaction_modal, true)
      |> assign(:create_action, :new)
      |> assign(:transcription_config, %TranscriptionConfig{})
    end
  end

  defp apply_action(socket, :edit_transcription, %{"id" => id}) do
    case Transcriptions.get_transcription_config_for_event(id, event_id(socket)) do
      nil ->
        socket
        |> put_flash(:error, gettext("Resource not found"))
        |> push_navigate(to: ~p"/e/#{socket.assigns.event.code}/manage")

      config ->
        socket
        |> assign(:create, "transcription")
        |> assign(:interaction_modal, true)
        |> assign(:create_action, :edit)
        |> assign(:transcription_config, config)
    end
  end

  @impl true
  def terminate(_reason, socket) do
    if Map.has_key?(socket.assigns, :event) do
      event = socket.assigns.event
      config = Map.get(socket.assigns, :transcription_config)

      if config && config.enabled do
        Claper.Transcriptions.TranscriptionWorker.stop(event.uuid)
      end
    end

    :ok
  end

  defp pin(post, socket) do
    {:ok, _updated_post} = Claper.Posts.toggle_pin_post(post)

    {:noreply, socket}
  end

  defp reply(post_id, reply_body, socket) do
    actor = {:user, socket.assigns.current_user, nil}

    case Claper.Posts.create_post_reply(socket.assigns.event, post_id, actor, reply_body) do
      {:ok, _reply} ->
        {:noreply, socket}

      {:error, reason} when reason in [:not_found, :forbidden] ->
        {:noreply, socket |> put_flash(:error, gettext("Resource not found"))}

      {:error, _changeset} ->
        {:noreply, socket |> put_flash(:error, gettext("Could not send the reply"))}
    end
  end

  defp ban(user, %{assigns: %{event: event, state: state}} = socket) do
    {:ok, new_state} =
      Claper.Presentations.update_presentation_state(state, %{
        "banned" => state.banned ++ ["#{user}"]
      })

    Phoenix.PubSub.broadcast(
      Claper.PubSub,
      "event:#{event.uuid}",
      {:banned, user}
    )

    {:noreply, socket |> assign(:state, new_state)}
  end

  defp interactions_at_position(
         %{assigns: %{event: event}} = socket,
         position,
         broadcast \\ false
       ) do
    with {:ok, interactions} <-
           Claper.Interactions.get_interactions_at_position(event, position, broadcast) do
      active = interactions |> Enum.find(& &1.enabled)

      socket
      |> assign(:interactions, interactions)
      |> assign(:current_interaction, active)
      |> assign(:word_cloud_words, word_cloud_words(active))
    end
  end

  defp word_cloud_words(%WordClouds.WordCloud{} = word_cloud),
    do: WordClouds.list_words(word_cloud)

  defp word_cloud_words(_interaction), do: []

  defp list_pinned_posts(_socket, event_id) do
    Claper.Posts.list_pinned_posts(event_id, [:event, :reactions])
    |> Enum.reverse()
  end

  defp list_all_posts(_socket, event_id) do
    Claper.Posts.list_posts(event_id, [:event, :reactions])
    |> Enum.reverse()
  end

  defp list_all_questions(_socket, event_id, sort \\ "date") do
    sort_atom =
      case sort do
        "likes" -> :likes
        _ -> :date
      end

    questions =
      Claper.Posts.list_questions(event_id, [:event, :reactions], sort_atom)
      |> Enum.filter(&(ClaperWeb.Helpers.body_without_links(&1.body) =~ "?"))

    if sort_atom == :date, do: Enum.reverse(questions), else: questions
  end

  # Turns an interaction on: the big screen starts from the interaction's own
  # "Show the results on the big screen" choice (Jose, 2026-11-14), then
  # phones and the big screen are told which interaction is current.
  defp activate(socket, interaction) do
    case Claper.Interactions.enable_interaction(interaction) do
      :ok ->
        {interaction, state} =
          Claper.Interactions.show_planned_results(interaction, socket.assigns.state)

        Phoenix.PubSub.broadcast(
          Claper.PubSub,
          "event:#{socket.assigns.event.uuid}",
          {:current_interaction, interaction}
        )

        {:noreply,
         socket
         |> assign(:state, state)
         |> assign(:current_interaction, interaction)
         |> interactions_at_position(state.position)}

      {:error, _reason} ->
        {:noreply, socket}
    end
  end

  defp list_form_submits(_socket, presentation_file_id) do
    Claper.Forms.list_form_submits(presentation_file_id, [:form])
  end

  defp refresh_event(%{assigns: %{event: event}} = socket) do
    refreshed_event = Events.get_event_with_code(event.code, @event_preload)

    socket
    |> assign(:event, refreshed_event)
    |> assign(:state, refreshed_event.presentation_file.presentation_state)
    |> assign(
      :missing_slide_thumbnails,
      Presentations.missing_slide_thumbnails?(refreshed_event.presentation_file)
    )
    |> assign(:thumbnail_cache_bust, thumbnail_cache_bust())
  end

  defp thumbnail_cache_bust do
    System.system_time(:second)
  end

  # The attendees' link and the event's code, each copied with a click
  # (Jose, 2026-11-14), after the title in the header at every width.
  attr :event, :map, required: true

  defp copy_link_and_code(assigns) do
    ~H"""
    <ClaperWeb.Component.CopyButton.copy_button
      id="copy-event-url"
      value={url(~p"/e/#{@event.code}")}
      label={gettext("URL")}
      description={gettext("Copy the link to this event")}
    />
    <ClaperWeb.Component.CopyButton.copy_button
      id="copy-event-code"
      value={String.upcase(@event.code)}
      label={"#" <> String.upcase(@event.code)}
      description={gettext("Copy this event's code")}
      class="font-mono tracking-wide"
    />
    """
  end

  # Start event, then Back to intro once started (docs/INTRO.md): one button
  # in the top bar, so the bar itself shows whether phones are on the intro
  # page. Both ask first. The words show from 1024px; narrower, the icon.
  attr :state, :map, required: true
  attr :class, :any, default: nil

  defp start_button(%{state: %{started: false}} = assigns) do
    ~H"""
    <button
      type="button"
      id={"start-event-#{if @class =~ "md:", do: "bar", else: "row"}"}
      class={["btn btn-primary btn-lg", @class]}
      phx-click="start-event"
      data-tooltip-side="bottom"
      data-tooltip={gettext("Start event")}
      aria-label={gettext("Start event")}
      data-confirm-title={gettext("Start the event?")}
      data-confirm={gettext("Everyone's phone moves from the intro page to your slides.")}
      data-confirm-action={gettext("Start event")}
    >
      <svg
        viewBox="0 0 24 24"
        fill="none"
        stroke="currentColor"
        stroke-width="2"
        class="size-4"
        aria-hidden="true"
      >
        <path
          stroke-linecap="round"
          stroke-linejoin="round"
          d="M3 3v1.5M3 21v-6m0 0 2.77-.693a9 9 0 0 1 6.208.682l.108.054a9 9 0 0 0 6.086.71l3.114-.732a48.524 48.524 0 0 1-.005-10.499l-3.11.732a9 9 0 0 1-6.085-.711l-.108-.054a9 9 0 0 0-6.208-.682L3 4.5M3 15V4.5"
        />
      </svg>
      <span class="hidden lg:inline">{gettext("Start event")}</span>
    </button>
    """
  end

  defp start_button(assigns) do
    ~H"""
    <button
      type="button"
      id={"back-to-intro-#{if @class =~ "md:", do: "bar", else: "row"}"}
      class={["btn btn-secondary btn-lg", @class]}
      phx-click="back-to-intro"
      data-tooltip-side="bottom"
      data-tooltip={gettext("Back to intro")}
      aria-label={gettext("Back to intro")}
      data-confirm-title={gettext("Go back to the intro page?")}
      data-confirm={gettext("Everyone's phone shows the intro page again until you start the event.")}
      data-confirm-action={gettext("Back to intro")}
    >
      <svg
        viewBox="0 0 24 24"
        fill="none"
        stroke="currentColor"
        stroke-width="2"
        class="size-4"
        aria-hidden="true"
      >
        <path
          stroke-linecap="round"
          stroke-linejoin="round"
          d="M9 15 3 9m0 0 6-6M3 9h12a6 6 0 0 1 0 12h-3"
        />
      </svg>
      <span class="hidden lg:inline">{gettext("Back to intro")}</span>
    </button>
    """
  end

  # Opens the intro page builder (docs/INTRO.md, decision 10). The words show
  # from 1280px; narrower, the icon alone (with its label for screen readers).
  attr :event, :map, required: true
  attr :class, :any, default: nil

  defp edit_intro_button(assigns) do
    ~H"""
    <.link
      navigate={~p"/e/#{@event.code}/intro"}
      id={"edit-intro-#{if @class =~ "md:", do: "bar", else: "row"}"}
      class={["btn btn-secondary btn-lg", @class]}
      aria-label={gettext("Edit intro")}
      data-tooltip-side="bottom"
      data-tooltip={gettext("Edit intro")}
    >
      <ClaperWeb.IntroLive.Components.icon kind="text" class="size-4" />
      <span class="hidden xl:inline">{gettext("Edit intro")}</span>
    </.link>
    """
  end

  # Opens the settings (phones and tablets; from 1280px they sit in the right
  # sidebar). One button, placed in the bar or in the row under it.
  attr :class, :any, default: nil

  defp settings_button(assigns) do
    ~H"""
    <button
      phx-click="toggle-settings-modal"
      aria-label={gettext("Settings")}
      class={["btn btn-secondary btn-circle btn-lg", @class]}
    >
      <svg
        xmlns="http://www.w3.org/2000/svg"
        viewBox="0 0 24 24"
        fill="currentColor"
        class="size-4"
        aria-hidden="true"
      >
        <path
          fill-rule="evenodd"
          d="M11.828 2.25c-.916 0-1.699.663-1.85 1.567l-.091.549a.798.798 0 0 1-.517.608 7.45 7.45 0 0 0-.478.198.798.798 0 0 1-.796-.064l-.453-.324a1.875 1.875 0 0 0-2.416.2l-.243.243a1.875 1.875 0 0 0-.2 2.416l.324.453a.798.798 0 0 1 .064.796 7.448 7.448 0 0 0-.198.478.798.798 0 0 1-.608.517l-.55.092a1.875 1.875 0 0 0-1.566 1.849v.344c0 .916.663 1.699 1.567 1.85l.549.091c.281.047.508.25.608.517.06.162.127.321.198.478a.798.798 0 0 1-.064.796l-.324.453a1.875 1.875 0 0 0 .2 2.416l.243.243c.648.648 1.67.733 2.416.2l.453-.324a.798.798 0 0 1 .796-.064c.157.071.316.137.478.198.267.1.47.327.517.608l.092.55c.15.903.932 1.566 1.849 1.566h.344c.916 0 1.699-.663 1.85-1.567l.091-.549a.798.798 0 0 1 .517-.608 7.52 7.52 0 0 0 .478-.198.798.798 0 0 1 .796.064l.453.324a1.875 1.875 0 0 0 2.416-.2l.243-.243c.648-.648.733-1.67.2-2.416l-.324-.453a.798.798 0 0 1-.064-.796c.071-.157.137-.316.198-.478.1-.267.327-.47.608-.517l.55-.091a1.875 1.875 0 0 0 1.566-1.85v-.344c0-.916-.663-1.699-1.567-1.85l-.549-.091a.798.798 0 0 1-.608-.517 7.507 7.507 0 0 0-.198-.478.798.798 0 0 1 .064-.796l.324-.453a1.875 1.875 0 0 0-.2-2.416l-.243-.243a1.875 1.875 0 0 0-2.416-.2l-.453.324a.798.798 0 0 1-.796.064 7.462 7.462 0 0 0-.478-.198.798.798 0 0 1-.517-.608l-.091-.55a1.875 1.875 0 0 0-1.85-1.566h-.344ZM12 15.75a3.75 3.75 0 1 0 0-7.5 3.75 3.75 0 0 0 0 7.5Z"
          clip-rule="evenodd"
        />
      </svg>
    </button>
    """
  end

  # Open presentation / Join, one segmented button group (tabs_component.ex).
  # Never hidden; it shrinks instead (Jose, 2026-11-13):
  #   :bar, 1024px and wider: "Open presentation" | "Join 0 attendees"
  #   :bar, 640 to 1023px:    "Present" | "Join · 0"
  #   :row (phones):          its own full-width row, two equal halves
  attr :event, :map, required: true
  attr :attendees_nb, :integer, required: true
  attr :variant, :atom, values: [:bar, :row], required: true

  defp present_join_group(assigns) do
    assigns =
      assign(assigns,
        sfx: if(assigns.variant == :row, do: "row-", else: ""),
        item: [
          "flex items-center justify-center gap-2 px-3 text-sm font-medium",
          assigns.variant == :row && "flex-1"
        ]
      )

    ~H"""
    <div
      class={[ClaperWeb.Component.Tabs.segmented_group_class(), @variant == :row && "w-full"]}
      role="group"
    >
      <button
        phx-hook="OpenPresenter"
        id={"openPresenter-#{@sfx}#{@event.uuid}"}
        data-url={~p"/e/#{@event.code}/presenter"}
        type="button"
        class={[@item, ClaperWeb.Component.Tabs.segmented_item_class(false)]}
      >
        <svg
          xmlns="http://www.w3.org/2000/svg"
          viewBox="0 0 24 24"
          fill="currentColor"
          class="size-4"
          aria-hidden="true"
        >
          <path
            fill-rule="evenodd"
            d="M4.5 5.653c0-1.427 1.529-2.33 2.779-1.643l11.54 6.347c1.295.712 1.295 2.573 0 3.286L7.28 19.99c-1.25.687-2.779-.217-2.779-1.643V5.653Z"
            clip-rule="evenodd"
          />
        </svg>
        <span :if={@variant == :bar} class="hidden lg:inline">{gettext("Open presentation")}</span>
        <span class={@variant == :bar && "lg:hidden"}>{gettext("Present")}</span>
      </button>
      <a
        href={~p"/e/#{@event.code}"}
        target="_blank"
        class={[@item, ClaperWeb.Component.Tabs.segmented_item_class(false)]}
      >
        <svg
          xmlns="http://www.w3.org/2000/svg"
          viewBox="0 0 24 24"
          fill="currentColor"
          class="size-4"
          aria-hidden="true"
        >
          <path
            fill-rule="evenodd"
            d="M8.25 6.75a3.75 3.75 0 1 1 7.5 0 3.75 3.75 0 0 1-7.5 0ZM15.75 9.75a3 3 0 1 1 6 0 3 3 0 0 1-6 0ZM2.25 9.75a3 3 0 1 1 6 0 3 3 0 0 1-6 0ZM6.31 15.117A6.745 6.745 0 0 1 12 12a6.745 6.745 0 0 1 6.709 7.498.75.75 0 0 1-.372.568A12.696 12.696 0 0 1 12 21.75c-2.305 0-4.47-.612-6.337-1.684a.75.75 0 0 1-.372-.568 6.787 6.787 0 0 1 1.019-4.38Z"
            clip-rule="evenodd"
          />
          <path d="M5.082 14.254a8.287 8.287 0 0 0-1.308 5.135 9.687 9.687 0 0 1-1.764-.44l-.115-.04a.563.563 0 0 1-.373-.487l-.01-.121a3.75 3.75 0 0 1 3.57-4.047ZM20.226 19.389a8.287 8.287 0 0 0-1.308-5.135 3.75 3.75 0 0 1 3.57 4.047l-.01.121a.563.563 0 0 1-.373.486l-.115.04c-.567.2-1.156.349-1.764.441Z" />
        </svg>
        <span>{gettext("Join")}</span>
        <span aria-hidden="true" class={["text-muted", @variant == :bar && "lg:hidden"]}>·</span>
        <span
          id={"attendees-count-#{@sfx}#{@event.uuid}"}
          phx-update="ignore"
          phx-hook="UpdateAttendees"
          data-label-id={"attendees-label-#{@sfx}#{@event.uuid}"}
          data-singular={gettext("attendee")}
          data-plural={gettext("attendees")}
        >
          {@attendees_nb}
        </span>
        <span
          id={"attendees-label-#{@sfx}#{@event.uuid}"}
          class={["hidden", @variant == :bar && "lg:inline"]}
        >
          {if @attendees_nb == 1, do: gettext("attendee"), else: gettext("attendees")}
        </span>
        <svg
          xmlns="http://www.w3.org/2000/svg"
          viewBox="0 0 24 24"
          fill="currentColor"
          class="size-4"
          aria-hidden="true"
        >
          <path
            fill-rule="evenodd"
            d="M8.25 3.75H19.5a.75.75 0 0 1 .75.75v11.25a.75.75 0 0 1-1.5 0V6.31L5.03 20.03a.75.75 0 0 1-1.06-1.06L17.69 5.25H8.25a.75.75 0 0 1 0-1.5Z"
            clip-rule="evenodd"
          />
        </svg>
      </a>
    </div>
    """
  end
end
