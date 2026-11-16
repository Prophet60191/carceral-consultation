defmodule ClaperWeb.MaterialsCardTest do
  use ClaperWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Claper.{EventsFixtures, PresentationsFixtures}

  alias Claper.Materials

  @pdf "%PDF-1.4\n%%EOF\n"
  @card "#settings-pane-materials"

  setup :register_and_log_in_user

  setup %{user: user} do
    event = event_fixture(%{user: user})

    presentation_file =
      presentation_file_fixture(%{
        event: event,
        hash: "card#{System.unique_integer([:positive])}"
      })

    presentation_state_fixture(%{presentation_file: presentation_file})
    on_exit(fn -> Materials.delete_event_files(event) end)
    %{event: event}
  end

  defp upload(view, name, contents) do
    file_input(view, "#materials-add-form", :pdf, [
      %{name: name, content: contents, type: "application/pdf"}
    ])
  end

  test "the card lists both kinds, with the slides switch and the closing time", %{
    conn: conn,
    event: event
  } do
    {:ok, view, _html} = live(conn, ~p"/e/#{event.code}/manage")

    assert has_element?(view, @card, "Materials")
    assert has_element?(view, @card, "Handouts")
    assert has_element?(view, @card, "Take-home")
    # No PDF of the slides on disk: the switch can't be turned on
    assert has_element?(view, "#{@card} button[role=switch][disabled]")
    assert has_element?(view, @card, "7 days after the event ends, unless you choose a time.")
  end

  test "+ → Handout → upload a PDF, also to take-home", %{conn: conn, event: event} do
    {:ok, view, _html} = live(conn, ~p"/e/#{event.code}/manage")

    view |> element("#{@card} button[aria-label='Add material']") |> render_click()
    assert has_element?(view, "#materials-add-window", "Add material")
    view |> element("#materials-add-window button", "Handout") |> render_click()
    assert has_element?(view, "#materials-add-window", "Add a handout")

    pdf = upload(view, "Sample letter.pdf", @pdf)
    assert render_upload(pdf, "Sample letter.pdf") =~ "Sample letter.pdf"

    # The title comes from the file name
    view
    |> form("#materials-add-form", material: %{title: ""})
    |> render_change()

    assert view |> element("#materials-add-form input[name='material[title]']") |> render() =~
             ~s(value="Sample letter")

    view
    |> form("#materials-add-form", material: %{title: "Sample letter", also_take_home: "true"})
    |> render_submit()

    refute has_element?(view, "#materials-add-window")
    assert [%{title: "Sample letter", enabled: true}] = Materials.list_materials(event, "handout")
    assert [%{title: "Sample letter"}] = Materials.list_materials(event, "take_home")
    assert view |> element(@card) |> render() =~ "Sample letter"
  end

  test "refuses a file that isn't a PDF, and asks for a title", %{conn: conn, event: event} do
    {:ok, view, _html} = live(conn, ~p"/e/#{event.code}/manage")
    view |> element("#{@card} button[aria-label='Add material']") |> render_click()
    view |> element("#materials-add-window button", "Take-home") |> render_click()

    fake = upload(view, "notes.pdf", "<html>nope</html>")
    render_upload(fake, "notes.pdf")

    view
    |> form("#materials-add-form", material: %{title: "Notes"})
    |> render_submit()

    assert has_element?(view, "#materials-add-window [role=alert]", "That file isn't a PDF.")
    assert Materials.list_materials(event, "take_home") == []
  end

  test "switch, reorder and remove", %{conn: conn, event: event} do
    path = Path.join(System.tmp_dir!(), "card-#{System.unique_integer([:positive])}.pdf")
    File.write!(path, @pdf)
    on_exit(fn -> File.rm(path) end)
    {:ok, [a]} = Materials.create_material(event, %{kind: "handout", title: "A"}, path)
    {:ok, [b]} = Materials.create_material(event, %{kind: "handout", title: "B"}, path)

    {:ok, view, _html} = live(conn, ~p"/e/#{event.code}/manage")

    view |> element("#{@card}-#{a.uuid} button[role=switch]") |> render_click()
    refute Claper.Repo.get!(Materials.Material, a.id).enabled

    view |> element("#{@card}-#{b.uuid} button[aria-label='Move up']") |> render_click()
    assert ["B", "A"] = event |> Materials.list_materials("handout") |> Enum.map(& &1.title)

    view |> element("#{@card}-#{b.uuid} button[aria-label='Remove']") |> render_click()
    assert ["A"] = event |> Materials.list_materials("handout") |> Enum.map(& &1.title)
    refute has_element?(view, "#{@card}-#{b.uuid}")
  end

  test "the closing time is set from the picker (UTC from the browser)", %{
    conn: conn,
    event: event
  } do
    {:ok, view, _html} = live(conn, ~p"/e/#{event.code}/manage")
    until = event.started_at |> NaiveDateTime.add(3 * 86_400) |> NaiveDateTime.truncate(:second)

    # The browser's DateTimeLocal hook fills the hidden UTC field
    view
    |> element("#{@card}-until")
    |> render_change(%{"take_home" => %{"take_home_until" => NaiveDateTime.to_iso8601(until)}})

    assert Claper.Repo.get!(Claper.Events.Event, event.id).take_home_until == until
    assert has_element?(view, @card, "The take-home page closes then.")
  end

  test "a change elsewhere shows up in the card", %{conn: conn, event: event} do
    {:ok, view, _html} = live(conn, ~p"/e/#{event.code}/manage")

    path = Path.join(System.tmp_dir!(), "card-#{System.unique_integer([:positive])}.pdf")
    File.write!(path, @pdf)
    on_exit(fn -> File.rm(path) end)
    {:ok, _} = Materials.create_material(event, %{kind: "take_home", title: "Guide"}, path)

    # The screen gets the change, then updates the card (send_update) as a
    # second message: one render lets that second message through first.
    render(view)
    assert view |> element(@card) |> render() =~ "Guide"
  end
end
