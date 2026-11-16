defmodule ClaperWeb.HandoutsRoomTest do
  use ClaperWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Claper.{EventsFixtures, PresentationsFixtures}

  alias Claper.Materials

  @pdf "%PDF-1.4\n%%EOF\n"

  setup do
    event = event_fixture(%{expired_at: nil})
    presentation_file = presentation_file_fixture(%{event: event})
    presentation_state_fixture(%{presentation_file: presentation_file, started: true})
    on_exit(fn -> Materials.delete_event_files(event) end)
    %{event: event}
  end

  defp add(event, title) do
    path = Path.join(System.tmp_dir!(), "ho-#{System.unique_integer([:positive])}.pdf")
    File.write!(path, @pdf)
    on_exit(fn -> File.rm(path) end)
    {:ok, [m]} = Materials.create_material(event, %{kind: "handout", title: title}, path)
    m
  end

  test "no icon without a handout switched on", %{conn: conn, event: event} do
    off = add(event, "Off")
    {:ok, _} = Materials.set_enabled(off, false)
    {:ok, view, _html} = live(conn, ~p"/e/#{event.code}")
    refute has_element?(view, "#room-handouts-toggle")
  end

  test "one handout: the icon opens it in the viewer, with download and close", %{
    conn: conn,
    event: event
  } do
    letter = add(event, "Sample letter")
    {:ok, view, _html} = live(conn, ~p"/e/#{event.code}")

    assert has_element?(view, "#room-handouts-toggle[aria-label='Handout: Sample letter']")
    view |> element("#room-handouts-toggle") |> render_click()

    assert has_element?(view, "#handout-viewer", "Sample letter")

    assert has_element?(
             view,
             "#handout-pdf-#{letter.uuid}[phx-hook=PdfViewer][phx-update=ignore]"
           )

    assert has_element?(
             view,
             ~s(#handout-pdf-#{letter.uuid}[data-src="/materials/#{letter.uuid}"])
           )

    assert has_element?(
             view,
             ~s(#handout-viewer a[download][href="/materials/#{letter.uuid}?download=1"])
           )

    view |> element("#handout-viewer button[phx-click=close_handout]") |> render_click()
    refute has_element?(view, "#handout-viewer")
  end

  test "several handouts: the icon opens their list", %{conn: conn, event: event} do
    add(event, "Worksheet")
    guide = add(event, "Resource guide")
    {:ok, view, _html} = live(conn, ~p"/e/#{event.code}")

    assert has_element?(view, "#room-handouts-toggle .handouts-count", "2")
    view |> element("#room-handouts-toggle") |> render_click()
    assert has_element?(view, "#room-handouts-menu", "Worksheet")

    view |> element("#room-handouts-menu button", "Resource guide") |> render_click()
    refute has_element?(view, "#room-handouts-menu")
    assert has_element?(view, "#handout-pdf-#{guide.uuid}")
  end

  test "switching a handout on or off shows at once; an open one closes", %{
    conn: conn,
    event: event
  } do
    letter = add(event, "Sample letter")
    {:ok, _} = Materials.set_enabled(letter, false)
    {:ok, view, _html} = live(conn, ~p"/e/#{event.code}")
    refute has_element?(view, "#room-handouts-toggle")

    {:ok, letter} = Materials.set_enabled(letter, true)
    assert has_element?(view, "#room-handouts-toggle")

    view |> element("#room-handouts-toggle") |> render_click()
    assert has_element?(view, "#handout-viewer")

    {:ok, _} = Materials.set_enabled(letter, false)
    refute has_element?(view, "#handout-viewer")
    refute has_element?(view, "#room-handouts-toggle")
  end
end
