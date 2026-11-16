defmodule ClaperWeb.MaterialsStatsTest do
  use ClaperWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Claper.{EventsFixtures, PresentationsFixtures}

  alias Claper.Materials

  setup :register_and_log_in_user

  test "the Materials tab: downloads per file and for the slides", %{conn: conn, user: user} do
    event = event_fixture(%{user: user})
    presentation_file = presentation_file_fixture(%{event: event})
    presentation_state_fixture(%{presentation_file: presentation_file})
    on_exit(fn -> Materials.delete_event_files(event) end)

    path = Path.join(System.tmp_dir!(), "ms-#{System.unique_integer([:positive])}.pdf")
    File.write!(path, "%PDF-1.4\n%%EOF\n")
    on_exit(fn -> File.rm(path) end)
    {:ok, [guide]} = Materials.create_material(event, %{kind: "take_home", title: "Guide"}, path)
    {:ok, [sheet]} = Materials.create_material(event, %{kind: "handout", title: "Sheet"}, path)
    {:ok, _} = Materials.set_enabled(sheet, false)
    Materials.record_download(guide)
    Materials.record_download(guide)
    {:ok, event} = Materials.set_take_home_slides(event, true)
    Materials.record_slides_download(event)

    {:ok, view, _html} = live(conn, ~p"/events/#{event.uuid}/stats")
    view |> element("button[phx-value-tab=materials]") |> render_click()

    assert has_element?(view, "#materials-report-#{guide.uuid}", "Guide")
    assert view |> element("#materials-report-#{guide.uuid}") |> render() =~ "2"
    assert has_element?(view, "#materials-report-#{sheet.uuid}", "Off")
    assert view |> element("#materials-report-slides") |> render() =~ "1"
  end
end
