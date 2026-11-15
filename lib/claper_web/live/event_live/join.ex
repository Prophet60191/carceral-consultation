defmodule ClaperWeb.EventLive.Join do
  use ClaperWeb, :live_view

  on_mount(ClaperWeb.AttendeeLiveAuth)

  @impl true
  def mount(params, session, socket) do
    with %{"locale" => locale} <- session do
      Gettext.put_locale(ClaperWeb.Gettext, locale)
    end

    # UUID only: integer ids are sequential and would allow enumerating events.
    last_event = Claper.Events.get_event_with_uuid(params["disconnected_from"])

    {:ok, socket |> assign(:last_event, last_event)}
  end

  @impl true
  def handle_params(params, _url, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  @impl true
  def handle_event("join", %{"event" => %{"code" => code}}, socket) do
    {:noreply, socket |> push_navigate(to: event_path(code))}
  end

  # The landing page (ClaperWeb.Landing): `/` opens closed, `/join` with the
  # Join panel open. The join form also works without LiveView: it submits
  # to /join?event[code]=…, which goes straight to the event.
  defp apply_action(socket, :join, %{"event" => %{"code" => code}}) when code != "" do
    redirect(socket, to: event_path(code))
  end

  defp apply_action(socket, action, _params) do
    socket
    |> assign(:page_title, gettext("Join"))
    |> assign(:event, nil)
    |> assign(:initial, if(action == :join, do: :join, else: :none))
  end

  defp event_path(code),
    do: ~p"/e/#{code |> String.trim() |> String.trim_leading("#") |> String.downcase()}"
end
