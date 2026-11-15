defmodule ClaperWeb.IntroLiveTest do
  @moduledoc "The intro page builder (docs/INTRO.md, step 2)."
  use ClaperWeb.ConnCase

  import Phoenix.LiveViewTest
  import Claper.{EventsFixtures, PresentationsFixtures}

  alias Claper.Intro

  setup :register_and_log_in_user

  setup %{user: user} do
    event = event_fixture(%{user: user})
    pf = presentation_file_fixture(%{event: event})
    presentation_state_fixture(%{presentation_file: pf})
    %{event: event, path: ~p"/e/#{event.code}/intro"}
  end

  test "the manage screen links to the builder", %{conn: conn, event: event, path: path} do
    {:ok, view, _html} = live(conn, ~p"/e/#{event.code}/manage")
    assert has_element?(view, ~s(a[href="#{path}"]), "Edit intro")
  end

  test "others can't open an event's intro builder", %{event: event} do
    stranger = Claper.AccountsFixtures.confirmed_user_fixture()

    assert {:error, {:redirect, %{to: "/events"}}} =
             build_conn() |> log_in_user(stranger) |> live(~p"/e/#{event.code}/intro")
  end

  test "blocks are added, shown in the preview, moved and removed", %{
    conn: conn,
    event: event,
    path: path
  } do
    {:ok, _view, html} = live(conn, path)
    assert html =~ ~s(src="#{path}/preview")
    # The builder's preview frame shows the real phone page; it follows changes.
    {:ok, pv, pv_html} = live(conn, "#{path}/preview")
    assert pv_html =~ "Welcome"
    assert has_element?(pv, "#intro .brand-lockup")
    assert has_element?(pv, "#intro .ticket", event.name)

    # A heading, through its dialog; a blank one is refused.
    {:ok, view, _} = live(conn, "#{path}?add=heading")
    view |> form("#block-form", block: %{text: ""}) |> render_submit()
    assert has_element?(view, "#block-editor", "can't be blank")

    view |> form("#block-form", block: %{text: "Tonight's session"}) |> render_submit()
    assert_patch(view, path)
    assert has_element?(pv, "#intro h2", "Tonight's session")

    # An agenda with rows added in the dialog.
    {:ok, view, _} = live(conn, "#{path}?add=agenda")
    view |> element("#block-form button", "Add an item") |> render_click()

    view
    |> form("#block-form",
      block: %{
        items: %{
          "0" => %{time: "6:00 PM", title: "Welcome"},
          "1" => %{time: "6:15 PM", title: "The parole board"}
        }
      }
    )
    |> render_submit()

    assert has_element?(pv, "#intro li", "The parole board")

    # A divider is added straight away; then moved up and removed.
    view |> element("button", "Divider") |> render_click()
    [_, _, _, divider] = Intro.get_event_page(event).blocks
    view |> element("#block-#{divider.id} button[phx-value-dir=up]") |> render_click()
    assert Enum.at(Intro.get_event_page(event).blocks, 2).kind == "divider"

    view |> element("#block-#{divider.id} button[phx-click=delete]") |> render_click()
    refute Enum.any?(Intro.get_event_page(event).blocks, &(&1.kind == "divider"))
  end

  test "an image is uploaded and shown", %{conn: conn, event: event, path: path} do
    {:ok, pv, _} = live(conn, "#{path}/preview")
    {:ok, view, _} = live(conn, "#{path}?add=image")

    image =
      file_input(view, "#block-form", :image, [
        %{name: "photo.png", content: "png-bytes", type: "image/png"}
      ])

    assert render_upload(image, "photo.png") =~ "photo.png"

    view
    |> form("#block-form", block: %{alt: "The hearing room", caption: "Albany"})
    |> render_submit()

    image_block = Enum.find(Intro.get_event_page(event).blocks, &(&1.kind == "image"))
    assert image_block.data["src"] =~ ~r{\A/uploads/intro/.+\.png\z}
    assert has_element?(pv, ~s(#intro img[alt="The hearing room"]))
  end

  test "editing keeps the saved values and saves changes", %{conn: conn, event: event, path: path} do
    [heading | _] = Intro.get_event_page(event).blocks
    {:ok, view, _} = live(conn, "#{path}?edit=#{heading.id}")
    assert view |> element("#block-form input[name='block[text]']") |> render() =~ "Welcome"

    view |> form("#block-form", block: %{text: "Welcome, everyone"}) |> render_submit()
    assert hd(Intro.get_event_page(event).blocks).data["text"] == "Welcome, everyone"
  end

  test "the brand switch hides the brand on the page and its preview", %{
    conn: conn,
    event: event,
    path: path
  } do
    {:ok, preview, _} = live(conn, ~p"/e/#{event.code}/intro/preview")
    assert has_element?(preview, ".intro-brand")

    {:ok, view, _html} = live(conn, path)
    assert has_element?(view, "#brand-setting", "Show the brand at the top")

    render_click(view, "checked", %{"key" => "show_brand", "value" => false})
    refute Intro.get_event_page(event).show_brand
    # The preview reloads when the builder announces the change
    refute has_element?(preview, ".intro-brand")

    render_click(view, "checked", %{"key" => "show_brand", "value" => true})
    assert Intro.get_event_page(event).show_brand
    assert has_element?(preview, ".intro-brand")
  end

  describe "the library" do
    test "pages are created, edited and deleted from the library", %{conn: conn, user: user} do
      {:ok, view, html} = live(conn, ~p"/intros")
      assert html =~ "Nothing saved yet"

      assert {:error, {:live_redirect, %{to: "/intros/" <> id}}} =
               view |> form("#intro-new", title: "Standard welcome") |> render_submit()

      {:ok, builder, html} = live(conn, ~p"/intros/#{id}")
      assert html =~ "Standard welcome"
      {:ok, pv, _} = live(conn, ~p"/intros/#{id}/preview")
      assert has_element?(pv, "#intro .ticket", "Standard welcome")
      refute has_element?(builder, "#intro-library")

      builder |> form("#library-name", title: "Welcome v2") |> render_change()
      assert [%{title: "Welcome v2"}] = Claper.Intro.list_library(user.id)

      {:ok, builder, _} = live(conn, ~p"/intros/#{id}?add=heading")
      builder |> form("#block-form", block: %{text: "Ground rules"}) |> render_submit()
      assert has_element?(pv, "#intro h2", "Ground rules")

      {:ok, view, _} = live(conn, ~p"/intros")
      view |> element("#intro-#{id} button[phx-click=delete]") |> render_click()
      assert Claper.Intro.list_library(user.id) == []
    end

    test "someone else's library page can't be opened", %{user: user} do
      {:ok, page} = Claper.Intro.create_library_page(user.id, "Mine")
      stranger = Claper.AccountsFixtures.confirmed_user_fixture()

      assert {:error, {:redirect, %{to: "/events"}}} =
               build_conn() |> log_in_user(stranger) |> live(~p"/intros/#{page.id}")
    end

    test "an event's page is saved to the library and replaced from it", %{
      conn: conn,
      user: user,
      event: event,
      path: path
    } do
      {:ok, view, _} = live(conn, path)
      view |> form("#save-to-library", title: "From this event") |> render_submit()
      assert [%{title: "From this event"} = saved] = Claper.Intro.list_library(user.id)

      lib = Claper.Intro.get_library_page(saved.id, user.id)
      {:ok, _} = Claper.Intro.add_block(lib, "stat", %{"value" => "3", "label" => "panels"})

      {:ok, pv, _} = live(conn, "#{path}/preview")
      {:ok, view, _} = live(conn, path)
      view |> form("#use-library", library_id: saved.id) |> render_submit()
      assert has_element?(pv, "#intro", "panels")
      assert length(Claper.Intro.get_event_page(event).blocks) == 2

      # The preview keeps following the event's (new) page.
      {:ok, view, _} = live(conn, "#{path}?add=heading")
      view |> form("#block-form", block: %{text: "After the swap"}) |> render_submit()
      assert has_element?(pv, "#intro h2", "After the swap")
    end

    test "the account menu links to the intro library", %{conn: conn} do
      html = conn |> get(~p"/events") |> html_response(200)
      assert html =~ ~s(href="/intros")
    end
  end
end
