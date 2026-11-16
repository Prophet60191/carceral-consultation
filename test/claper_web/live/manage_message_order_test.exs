defmodule ClaperWeb.ManageMessageOrderTest do
  @moduledoc "Staff message lists in chat order (Jose, 2026-11-16)."
  use ClaperWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Claper.{EventsFixtures, PresentationsFixtures, PostsFixtures}

  setup :register_and_log_in_user

  setup %{user: user} do
    event = event_fixture(%{user: user})
    presentation_file = presentation_file_fixture(%{event: event})
    presentation_state_fixture(%{presentation_file: presentation_file})
    %{event: event}
  end

  defp bodies(view, list) do
    view
    |> element(list)
    |> render()
    |> Floki.parse_fragment!()
    |> Floki.find("[data-post-bubble]")
    # The bubble also holds its like count and question mark: keep the text
    |> Enum.map(fn bubble ->
      [body] =
        Regex.run(~r/First|Second|Third|Older question\?|Newer question\?/, Floki.text(bubble))

      body
    end)
  end

  test "messages: oldest first, a new one at the bottom; the list follows the newest", %{
    conn: conn,
    user: user,
    event: event
  } do
    post_fixture(%{event: event, user: user, body: "First"})
    post_fixture(%{event: event, user: user, body: "Second"})

    {:ok, view, _html} = live(conn, ~p"/e/#{event.code}/manage")
    assert ["First", "Second"] = bodies(view, "#post-list")
    assert has_element?(view, "#post-list[phx-hook=RoomFeed][data-item-prefix='posts-']")

    {:ok, third} =
      Claper.Posts.create_post(event, %{body: "Third", user_id: user.id, position: 0})

    Phoenix.PubSub.broadcast(Claper.PubSub, "event:#{event.uuid}", {:post_created, third})
    assert ["First", "Second", "Third"] = bodies(view, "#post-list")
  end

  test "questions: by date in chat order; by likes most liked at the top", %{
    conn: conn,
    user: user,
    event: event
  } do
    post_fixture(%{event: event, user: user, body: "Older question?", like_count: 1})
    post_fixture(%{event: event, user: user, body: "Newer question?", like_count: 9})

    {:ok, view, _html} = live(conn, ~p"/e/#{event.code}/manage")
    view |> element("#menu button[phx-value-tab=questions]") |> render_click()
    assert ["Older question?", "Newer question?"] = bodies(view, "#question-list")
    assert has_element?(view, "#question-list[data-follow=true]")

    view |> element("button[phx-value-sort=likes]") |> render_click()
    assert ["Newer question?", "Older question?"] = bodies(view, "#question-list")
    assert has_element?(view, "#question-list[data-follow=false]")
  end
end
