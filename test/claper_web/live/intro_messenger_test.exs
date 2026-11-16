defmodule ClaperWeb.IntroMessengerTest do
  @moduledoc """
  The intro page's messenger (Jose, 2026-11-15): before the start, when
  messages are on, people can open a messenger and talk; a red dot shows
  messages that arrived while it was closed.
  """
  use ClaperWeb.ConnCase

  import Phoenix.LiveViewTest
  import Claper.{EventsFixtures, PresentationsFixtures}

  alias Claper.{Posts, Presentations}

  setup do
    event = event_fixture()
    pf = presentation_file_fixture(%{event: event})

    state =
      presentation_state_fixture(%{
        presentation_file: pf,
        started: false,
        chat_enabled: true,
        anonymous_chat_enabled: true
      })

    %{event: event, state: state}
  end

  defp phone(event, id) do
    conn =
      Phoenix.ConnTest.build_conn() |> Plug.Test.init_test_session(%{attendee_identifier: id})

    {:ok, view, _html} = live(conn, ~p"/e/#{event.code}")
    view
  end

  test "the bubble opens and closes the messenger, with the same message box as the live room",
       %{event: event} do
    a = phone(event, "intro-a")
    assert has_element?(a, "#intro")
    assert has_element?(a, ~s(#intro-messenger[data-open="false"]))
    assert has_element?(a, "#intro-messenger-panel[inert]")

    a |> element("#intro-messenger-toggle") |> render_click()
    assert has_element?(a, ~s(#intro-messenger[data-open="true"]))
    refute has_element?(a, "#intro-messenger-panel[inert]")
    assert has_element?(a, "#intro-messenger #post-form #postFormTA")
    assert has_element?(a, "#intro-messenger #chat-feed")
    assert has_element?(a, ~s(#intro-messenger.messenger[phx-hook="Messenger"]))
    assert has_element?(a, "#intro-messenger #messenger-composer #post-form")

    a |> element("#intro-messenger-toggle") |> render_click()
    assert has_element?(a, ~s(#intro-messenger[data-open="false"]))

    a |> element("#intro-messenger-toggle") |> render_click()
    render_hook(a, "close-messenger", %{})
    assert has_element?(a, ~s(#intro-messenger[data-open="false"]))
  end

  test "a message sent before the start reaches everyone; the red dot marks others' messages",
       %{event: event} do
    a = phone(event, "intro-a")
    b = phone(event, "intro-b")

    a |> element("#intro-messenger-toggle") |> render_click()
    a |> form("#post-form", post: %{body: "Is there parking nearby?"}) |> render_submit()

    assert [%{body: "Is there parking nearby?"}] = Posts.list_posts(event.uuid)
    # The sender's messenger is open: no dot for them
    refute has_element?(a, "#intro-messenger-dot")

    # B's messenger is closed: the message shows in the feed and the dot appears
    assert render(b) =~ "Is there parking nearby?"
    assert has_element?(b, "#intro-messenger-dot")

    # Opening clears it
    b |> element("#intro-messenger-toggle") |> render_click()
    refute has_element?(b, "#intro-messenger-dot")
  end

  test "your own message never lights the dot", %{event: event} do
    a = phone(event, "intro-a")
    a |> element("#intro-messenger-toggle") |> render_click()
    a |> form("#post-form", post: %{body: "Hello everyone"}) |> render_submit()
    a |> element("#intro-messenger-toggle") |> render_click()

    {:ok, _} =
      Posts.create_attendee_post(event, {:attendee, "intro-a", ""}, %{"body" => "Another one"})

    refute has_element?(a, "#intro-messenger-dot")
  end

  test "the theme button sits in the corner, with or without messages", %{
    event: event,
    state: state
  } do
    a = phone(event, "intro-theme")
    assert has_element?(a, "#intro-theme #intro-theme-toggle[data-theme-toggle]")
    assert has_element?(a, ~s(#intro-theme-toggle[data-label-light="Switch to light theme"]))
    assert has_element?(a, ~s(#intro-theme-toggle[data-label-dark="Switch to dark theme"]))

    {:ok, _} = Presentations.update_presentation_state(state, %{chat_enabled: false})
    off = phone(event, "intro-theme-off")
    assert has_element?(off, "#intro-theme-toggle")
    refute has_element?(off, "#intro-messenger")
  end

  test "no messenger when messages are off, or once the event has started",
       %{event: event, state: state} do
    {:ok, state} = Presentations.update_presentation_state(state, %{chat_enabled: false})
    off = phone(event, "intro-off")
    assert has_element?(off, "#intro")
    refute has_element?(off, "#intro-messenger")

    {:ok, _} =
      Presentations.update_presentation_state(state, %{
        chat_enabled: true,
        started: true
      })

    live_room = phone(event, "intro-live")
    refute has_element?(live_room, "#intro")
    refute has_element?(live_room, "#intro-messenger")
    assert has_element?(live_room, "#attendee-room #post-form")
  end
end
