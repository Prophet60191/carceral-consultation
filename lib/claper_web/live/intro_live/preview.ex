defmodule ClaperWeb.IntroLive.Preview do
  @moduledoc """
  The builder's phone preview (docs/INTRO.md): the real intro screen a
  participant's phone shows (brand, ticket with banner and countdown,
  blocks), drawn by the same component, at `/e/<code>/intro/preview` or
  `/intros/<id>/preview`. The builder shows it in a phone-width frame, so it
  uses the true phone layout; it reloads when the builder changes the page
  (`{:intro_page_updated, id}` on `"intro_page:<id>"`).

  A library page has no event: its name stands in for the title and the
  countdown runs to a sample start an hour away.
  """
  use ClaperWeb, :live_view

  on_mount(ClaperWeb.UserLiveAuth)

  alias Claper.Intro

  @impl true
  def mount(params, _session, socket) do
    case scope(socket, params) do
      {:ok, event, page} ->
        if connected?(socket) do
          Phoenix.PubSub.subscribe(Claper.PubSub, "intro_page:#{page.id}")
          :timer.send_interval(1000, self(), :tick)
        end

        {:ok,
         socket
         |> assign(page_title: gettext("Phone preview"), event: event)
         |> assign_page(page)
         |> assign_countdown()}

      :error ->
        {:ok, redirect(socket, to: ~p"/events")}
    end
  end

  defp scope(socket, %{"code" => code}) do
    user = socket.assigns.current_user
    event = Claper.Events.get_event_with_code(code, [:user])

    if event && (event.user_id == user.id || Claper.Events.led_by?(user.email, event)),
      do: {:ok, event, Intro.ensure_event_page(event)},
      else: :error
  end

  defp scope(socket, %{"id" => id}) do
    case Intro.get_library_page(id, socket.assigns.current_user.id) do
      nil ->
        :error

      page ->
        start =
          NaiveDateTime.utc_now() |> NaiveDateTime.add(3600) |> NaiveDateTime.truncate(:second)

        {:ok, %{name: page.title, started_at: start}, page}
    end
  end

  @impl true
  def handle_info(:tick, socket), do: {:noreply, assign_countdown(socket)}

  def handle_info({:intro_page_updated, _id}, socket) do
    page =
      case socket.assigns.event do
        %Claper.Events.Event{} = event -> Intro.ensure_event_page(event)
        _ -> Intro.get_library_page(socket.assigns.page.id, socket.assigns.current_user.id)
      end

    page = page || socket.assigns.page

    # Using a library page gives the event a new page: listen to that one now.
    if page.id != socket.assigns.page.id do
      Phoenix.PubSub.unsubscribe(Claper.PubSub, "intro_page:#{socket.assigns.page.id}")
      Phoenix.PubSub.subscribe(Claper.PubSub, "intro_page:#{page.id}")
    end

    {:noreply, assign_page(socket, page)}
  end

  defp assign_page(socket, page) do
    contents =
      for block <- page.blocks,
          Intro.Block.interaction?(block),
          into: %{},
          do: {block.id, Intro.load_content(block)}

    socket |> assign(:page, page) |> assign(:contents, contents)
  end

  # The same countdown the phones show (EventLive.Show), recomputed each second.
  defp assign_countdown(socket) do
    left =
      max(
        0,
        NaiveDateTime.diff(socket.assigns.event.started_at, NaiveDateTime.utc_now())
      )

    countdown =
      if left > 0,
        do: %{
          days: div(left, 86_400),
          hours: rem(left, 86_400) |> div(3600),
          minutes: rem(left, 3600) |> div(60),
          seconds: rem(left, 60)
        }

    assign(socket, :countdown, countdown)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <ClaperWeb.IntroLive.Components.intro_screen
      id="intro"
      event={@event}
      blocks={@page.blocks}
      contents={@contents}
      countdown={@countdown}
      banner_src={@page.banner_src}
      banner_alt={@page.banner_alt}
      show_brand={@page.show_brand}
    />
    """
  end
end
