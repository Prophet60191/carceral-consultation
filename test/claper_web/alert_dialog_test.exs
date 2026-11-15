defmodule ClaperWeb.AlertDialogTest do
  @moduledoc """
  The app's confirmation dialog replaces the browser's confirm()
  (ClaperWeb.AlertDialog, assets/js/alert_dialog.js; Jose, 2026-11-14).
  """
  use ClaperWeb.ConnCase

  import Phoenix.LiveViewTest
  import Claper.{EventsFixtures, PollsFixtures, PresentationsFixtures}

  setup :register_and_log_in_user

  test "every page carries the dialog, with its default wording", %{conn: conn} do
    html = conn |> get(~p"/events") |> html_response(200)
    assert html =~ ~s(id="cc-alert-dialog")
    assert html =~ ~s(role="alertdialog")
    assert html =~ ~s(data-default-title="Are you sure?")
    assert html =~ ~s(data-default-action="Continue")
  end

  test "a delete asks with a title, a named button and the destructive style", %{
    conn: conn,
    user: user
  } do
    event = event_fixture(%{user: user})
    pf = presentation_file_fixture(%{event: event})
    presentation_state_fixture(%{presentation_file: pf})
    poll = poll_fixture(%{presentation_file_id: pf.id, position: 0, enabled: false})

    {:ok, view, _html} = live(conn, ~p"/e/#{event.code}/manage/edit/poll/#{poll.id}")
    delete = view |> element("a[phx-click=delete]") |> render()

    assert delete =~ ~s(data-confirm-title="Delete this poll?")
    assert delete =~ ~s(data-confirm="All its votes are deleted too. This cannot be undone.")
    assert delete =~ ~s(data-confirm-action="Delete")
    assert delete =~ ~s(data-confirm-variant="destructive")
  end
end
