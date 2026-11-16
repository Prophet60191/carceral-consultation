defmodule ClaperWeb.TakeHomeTest do
  use ClaperWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Claper.{EventsFixtures, PresentationsFixtures}

  alias Claper.Materials

  @pdf "%PDF-1.4\n%%EOF\n"

  defp minutes(n),
    do: NaiveDateTime.add(NaiveDateTime.utc_now(), n * 60) |> NaiveDateTime.truncate(:second)

  setup do
    event = event_fixture(%{started_at: minutes(-120), expired_at: nil})
    presentation_file = presentation_file_fixture(%{event: event})
    presentation_state_fixture(%{presentation_file: presentation_file, started: true})
    on_exit(fn -> Materials.delete_event_files(event) end)
    %{event: event}
  end

  defp add(event, kind, title) do
    path = Path.join(System.tmp_dir!(), "th-#{System.unique_integer([:positive])}.pdf")
    File.write!(path, @pdf)
    on_exit(fn -> File.rm(path) end)
    {:ok, [m]} = Materials.create_material(event, %{kind: kind, title: title}, path)
    m
  end

  defp end_event(event) do
    {:ok, event} =
      event |> Ecto.Changeset.change(expired_at: minutes(-1)) |> Claper.Repo.update()

    event
  end

  test "when the event ends, phones in the room go to the take-home page", %{
    conn: conn,
    event: event
  } do
    add(event, "take_home", "Resource guide")
    {:ok, view, _html} = live(conn, ~p"/e/#{event.code}")

    {:ok, _} = Claper.Events.terminate_event(event)
    assert_redirect(view, ~p"/e/#{event.code}/take-home")
  end

  test "with nothing to take home, the end goes home as before", %{conn: conn, event: event} do
    {:ok, view, _html} = live(conn, ~p"/e/#{event.code}")
    {:ok, _} = Claper.Events.terminate_event(event)
    assert_redirect(view, ~p"/")
  end

  test "the page: the files switched on, each with a download; the closing time", %{
    conn: conn,
    event: event
  } do
    guide = add(event, "take_home", "Resource guide")
    hidden = add(event, "take_home", "Draft")
    {:ok, _} = Materials.set_enabled(hidden, false)
    handout = add(event, "handout", "Worksheet")
    event = end_event(event)

    {:ok, view, _html} = live(conn, ~p"/e/#{event.code}/take-home")

    assert has_element?(view, "#take-home", event.name)
    assert has_element?(view, "#take-home-#{guide.uuid}", "Resource guide")

    assert has_element?(
             view,
             ~s(#take-home-#{guide.uuid} a[download][href="/materials/#{guide.uuid}?download=1"])
           )

    refute has_element?(view, "#take-home-#{hidden.uuid}")
    refute has_element?(view, "#take-home-#{handout.uuid}")
    refute has_element?(view, "#take-home-slides")

    until = NaiveDateTime.to_iso8601(Materials.take_home_until(event))
    assert has_element?(view, ~s(#take-home-until[phx-hook=LocalDate][data-utc="#{until}"]))
  end

  test "opening the event's link after the end leads here", %{conn: conn, event: event} do
    add(event, "take_home", "Resource guide")
    event = end_event(event)

    assert {:error, {:redirect, %{to: to}}} = live(conn, ~p"/e/#{event.code}")
    assert to == ~p"/e/#{event.code}/take-home"
  end

  test "after the closing time: no longer available", %{conn: conn, event: event} do
    guide = add(event, "take_home", "Resource guide")
    event = end_event(event)

    {:ok, _} =
      event |> Ecto.Changeset.change(take_home_until: minutes(0)) |> Claper.Repo.update()

    {:ok, view, _html} = live(conn, ~p"/e/#{event.code}/take-home")
    assert has_element?(view, "#take-home-closed")
    refute has_element?(view, "#take-home-#{guide.uuid}")
  end

  test "switching a file on shows it at once", %{conn: conn, event: event} do
    guide = add(event, "take_home", "Resource guide")
    {:ok, _} = Materials.set_enabled(guide, false)
    {:ok, _} = Materials.set_take_home_slides(event, false)
    add(event, "take_home", "Other")
    event = end_event(event)

    {:ok, view, _html} = live(conn, ~p"/e/#{event.code}/take-home")
    refute has_element?(view, "#take-home-#{guide.uuid}")

    {:ok, _} = Materials.set_enabled(guide, true)
    assert has_element?(view, "#take-home-#{guide.uuid}")
  end

  test "a running event sends people back to the room", %{conn: conn, event: event} do
    assert {:error, {:live_redirect, %{to: to}}} = live(conn, ~p"/e/#{event.code}/take-home")
    assert to == ~p"/e/#{event.code}"
  end
end
