defmodule ClaperWeb.EventLive.SettingsPanelsTest do
  @moduledoc """
  The manage screen's settings: every message switch sits in one Message
  Settings panel, and the attendee count is right (Jose, 2026-11-14).
  """
  use ClaperWeb.ConnCase

  import Phoenix.LiveViewTest
  import Claper.PresentationsFixtures

  setup [:register_and_log_in_user]

  test "message switches are together in Message Settings", %{conn: conn, user: user} do
    pf = presentation_file_fixture(%{user: user}, [:event])
    presentation_state_fixture(%{presentation_file: pf})

    {:ok, manage, _} = live(conn, ~p"/e/#{pf.event.code}/manage")
    html = manage |> element("#settings-modal-content") |> render()

    panels =
      html
      |> Floki.parse_fragment!()
      |> Floki.find(".panel")
      |> Map.new(fn panel ->
        title = panel |> Floki.find(".panel-header span") |> Floki.text() |> String.trim()
        labels = panel |> Floki.find("button[role=switch]") |> Floki.attribute("aria-label")
        {title, labels}
      end)

    assert panels["Message Settings"] == [
             "Allow messages",
             "Allow anonymous messages",
             "Allow reactions",
             "Show messages on big screen",
             "Show only pinned messages"
           ]

    assert panels["Presentation Settings"] == ["Show join instructions", "Show attendee count"]
    refute Map.has_key?(panels, "Attendee Settings")
  end

  test "the attendee count is right when a screen opens and when the badge is switched on",
       %{conn: conn, user: user} do
    pf = presentation_file_fixture(%{user: user}, [:event])
    presentation_state_fixture(%{presentation_file: pf, show_attendee_count: false})
    event = pf.event

    # Two phones are already in before either screen opens.
    for id <- ["phone-a", "phone-b"] do
      conn =
        Phoenix.ConnTest.build_conn() |> Plug.Test.init_test_session(%{attendee_identifier: id})

      {:ok, _phone, _} = live(conn, ~p"/e/#{event.code}")
    end

    {:ok, screen, _} = live(conn, ~p"/e/#{event.code}/presenter")
    {:ok, manage, _} = live(conn, ~p"/e/#{event.code}/manage")
    refute has_element?(screen, "#counter")
    assert render(manage) =~ ~r/>\s*2\s*<\/span>/

    toggle = ~s(#settings-modal-content button[phx-value-key="show_attendee_count"])
    manage |> element(toggle) |> render_click()
    assert screen |> element("#counter") |> render() =~ ~r/>\s*2\s*</

    # A third phone joins: both screens hear about it.
    conn3 =
      Phoenix.ConnTest.build_conn()
      |> Plug.Test.init_test_session(%{attendee_identifier: "phone-c"})

    {:ok, _phone, _} = live(conn3, ~p"/e/#{event.code}")
    assert_push_event(screen, "update-attendees", %{count: 3})
    assert_push_event(manage, "update-attendees", %{count: 3})
  end
end
