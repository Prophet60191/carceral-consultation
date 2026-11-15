defmodule ClaperWeb.EmbedLive.FormComponent do
  use ClaperWeb, :live_component

  alias Claper.Embeds
  alias Claper.Embeds.{Embed, FrameCheck}

  @impl true
  def update(%{embed: embed} = assigns, socket) do
    changeset = Embeds.change_embed(embed)

    {:ok,
     socket
     |> assign(assigns)
     |> assign_new(:dark, fn -> false end)
     |> assign_new(:piece_target, fn -> nil end)
     |> assign(:embeds, list_embeds(assigns))
     |> assign(:providers, [
       {"YouTube", "youtube"},
       {"Vimeo", "vimeo"},
       {"Canva", "canva"},
       {"Google Slides", "googleslides"},
       {"Website", "website"},
       {"Custom (iframe)", "custom"}
     ])
     |> assign(:changeset, changeset)
     |> assign_new(:checked_url, fn -> nil end)
     |> assign_new(:frame_check, fn -> nil end)
     |> maybe_check_frame(changeset)}
  end

  @impl true
  def handle_event("delete", %{"id" => id}, socket) do
    case Embeds.get_embed_for_event(id, socket.assigns.presentation_file.event_id) do
      nil ->
        ClaperWeb.SecurityAudit.observe(socket, "embed", nil, "resource_not_found")

        {:noreply, socket}

      embed ->
        {:ok, _} = Embeds.delete_embed(socket.assigns.event_uuid, embed)
        {:noreply, socket |> push_navigate(to: socket.assigns.return_to)}
    end
  end

  @impl true
  def handle_event("validate", %{"embed" => embed_params}, socket) do
    changeset =
      socket.assigns.embed
      |> Embeds.change_embed(embed_params)
      |> Map.put(:action, :validate)

    {:noreply, socket |> assign(:changeset, changeset) |> maybe_check_frame(changeset)}
  end

  @impl true
  def handle_event(
        "save",
        %{"embed" => embed_params},
        %{assigns: %{piece_target: target}} = socket
      )
      when not is_nil(target),
      do:
        ClaperWeb.BreakoutLive.PieceEditor.save(
          socket,
          "embed",
          Claper.Embeds.Embed,
          embed_params
        )

  def handle_event("save", %{"embed" => embed_params}, socket) do
    save_embed(socket, socket.assigns.live_action, embed_params)
  end

  # "Website" addresses: ask the site, in the background, whether it allows
  # being shown in a frame, so the form can warn before it shows up blank.
  @impl true
  def handle_async(:frame_check, {:ok, {url, result}}, socket) do
    if url == socket.assigns.checked_url,
      do: {:noreply, assign(socket, :frame_check, result)},
      else: {:noreply, socket}
  end

  def handle_async(:frame_check, {:exit, _reason}, socket) do
    {:noreply, assign(socket, :frame_check, :unknown)}
  end

  defp maybe_check_frame(socket, changeset) do
    with "website" <- Ecto.Changeset.get_field(changeset, :provider),
         {:ok, url} <-
           Embed.provider_embed_url("website", Ecto.Changeset.get_field(changeset, :content)) do
      if url == socket.assigns.checked_url do
        socket
      else
        socket
        |> assign(checked_url: url, frame_check: :checking)
        |> start_async(:frame_check, fn -> {url, FrameCheck.check(url)} end)
      end
    else
      _ -> assign(socket, checked_url: nil, frame_check: nil)
    end
  end

  defp save_embed(socket, :edit, embed_params) do
    case Embeds.update_embed(
           socket.assigns.event_uuid,
           socket.assigns.embed,
           embed_params
         ) do
      {:ok, _embed} ->
        ClaperWeb.SecurityAudit.observe(
          socket,
          "embed",
          socket.assigns.embed.id,
          "submission_burst",
          20
        )

        {:noreply,
         socket
         |> push_navigate(to: socket.assigns.return_to)}

      {:error, %Ecto.Changeset{} = changeset} ->
        ClaperWeb.SecurityAudit.observe(
          socket,
          "embed",
          socket.assigns.embed.id,
          "validation_rejected"
        )

        {:noreply, assign(socket, :changeset, changeset)}
    end
  end

  defp save_embed(socket, :new, embed_params) do
    case Embeds.create_embed(
           embed_params
           |> Map.put("presentation_file_id", socket.assigns.presentation_file.id)
           |> Map.put("position", socket.assigns.position)
           |> Map.put("enabled", false)
         ) do
      {:ok, embed} ->
        ClaperWeb.SecurityAudit.observe(socket, "embed", embed.id, "submission_burst", 20)

        {:noreply,
         socket
         |> maybe_change_current_embed(embed)
         |> push_navigate(to: socket.assigns.return_to)}

      {:error, %Ecto.Changeset{} = changeset} ->
        ClaperWeb.SecurityAudit.observe(socket, "embed", nil, "validation_rejected")

        {:noreply, assign(socket, changeset: changeset)}
    end
  end

  defp maybe_change_current_embed(socket, %{enabled: true} = embed) do
    embed = Embeds.get_embed!(embed.id)

    Phoenix.PubSub.broadcast(
      Claper.PubSub,
      "event:#{socket.assigns.event_uuid}",
      {:current_embed, embed}
    )

    socket
  end

  defp maybe_change_current_embed(socket, _), do: socket

  defp list_embeds(%{presentation_file: %{id: id}}), do: Embeds.list_embeds(id)
  defp list_embeds(_assigns), do: []
end
