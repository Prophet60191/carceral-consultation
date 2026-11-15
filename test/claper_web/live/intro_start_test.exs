defmodule ClaperWeb.IntroStartTest do
  @moduledoc "Start Event and the intro page on phones (docs/INTRO.md, step 3)."
  use ClaperWeb.ConnCase

  import Phoenix.LiveViewTest
  import Claper.{EventsFixtures, PresentationsFixtures}

  alias Claper.Intro

  setup :register_and_log_in_user

  setup %{user: user} do
    event = event_fixture(%{user: user})
    pf = presentation_file_fixture(%{event: event})
    presentation_state_fixture(%{presentation_file: pf, started: false})
    page = Intro.get_event_page(event)
    {:ok, _} = Intro.add_block(page, "stat", %{"value" => "26 years", "label" => "served"})
    %{event: event}
  end

  defp phone(event, id) do
    conn =
      Phoenix.ConnTest.build_conn() |> Plug.Test.init_test_session(%{attendee_identifier: id})

    {:ok, view, _html} = live(conn, ~p"/e/#{event.code}")
    view
  end

  test "phones show the intro page until the presenter starts, and again after Back to intro",
       %{conn: conn, event: event} do
    a = phone(event, "phone-a")
    assert has_element?(a, "#intro", event.name)
    assert has_element?(a, "#intro .intro-blocks", "26 years")
    refute has_element?(a, "#intro #qr")

    {:ok, manage, _} = live(conn, ~p"/e/#{event.code}/manage")
    assert has_element?(manage, "#start-event-bar", "Start event")
    refute has_element?(manage, "#back-to-intro-bar")
    refute has_element?(manage, "#intro-strip")

    manage |> element("#start-event-bar") |> render_click()
    refute has_element?(a, "#intro")
    refute has_element?(manage, "#start-event-bar")
    assert has_element?(manage, "#back-to-intro-bar", "Back to intro")

    # Latecomers after the start go straight to the slides.
    b = phone(event, "phone-b")
    refute has_element?(b, "#intro")

    # About this event: the intro page over the slides.
    b |> element("#about-event") |> render_click()
    assert has_element?(b, "#about-overlay", "26 years")
    b |> element("#about-overlay button", "Back to the event") |> render_click()
    refute has_element?(b, "#about-overlay")

    manage |> element("#back-to-intro-bar") |> render_click()

    assert has_element?(a, "#intro")
    assert has_element?(b, "#intro")
    assert has_element?(manage, "#start-event-bar")
  end

  test "the big screen shows the join page with the start time until the start", %{
    conn: conn,
    event: event
  } do
    {:ok, screen, _} = live(conn, ~p"/e/#{event.code}/presenter")
    assert screen |> element("#joinScreen") |> render() =~ "opacity-100"
    assert has_element?(screen, "#join-start #join-start-countdown[phx-hook=StartCountdown]")

    {:ok, manage, _} = live(conn, ~p"/e/#{event.code}/manage")
    manage |> element("#start-event-bar") |> render_click()

    assert screen |> element("#joinScreen") |> render() =~ "opacity-0"
    refute has_element?(screen, "#join-start")
  end

  test "a banner is uploaded in the builder and shown on the phones' ticket card", %{
    conn: conn,
    event: event
  } do
    a = phone(event, "phone-a")
    refute has_element?(a, "#intro .intro-banner")
    {:ok, pv, _} = live(conn, ~p"/e/#{event.code}/intro/preview")

    {:ok, builder, _} = live(conn, ~p"/e/#{event.code}/intro")

    banner =
      file_input(builder, "#banner-form", :banner, [
        %{name: "cover.jpg", content: "jpg-bytes", type: "image/jpeg"}
      ])

    render_upload(banner, "cover.jpg")
    builder |> form("#banner-form", banner_alt: "The courthouse") |> render_submit()

    assert has_element?(a, ~s(#intro .ticket img.intro-banner[alt="The courthouse"]))
    assert has_element?(pv, ~s(#intro .ticket img.intro-banner[alt="The courthouse"]))

    builder |> element("#banner-form button", "Remove") |> render_click()
    refute has_element?(a, "#intro .intro-banner")
  end

  test "interactions are added in the builder and answered on phones until the start", %{
    conn: conn,
    event: event
  } do
    a = phone(event, "phone-a")
    {:ok, pv, _} = live(conn, ~p"/e/#{event.code}/intro/preview")

    # A poll, with its usual editor (no Group answer box on the intro page).
    path = ~p"/e/#{event.code}/intro"
    {:ok, builder, html} = live(conn, "#{path}?add=poll")
    refute html =~ "Group answer"

    assert {:error, {:live_redirect, %{to: ^path}}} =
             builder
             |> form("#poll-form",
               poll: %{
                 title: "Have you been to a parole hearing?",
                 poll_opts: %{"0" => %{content: "Yes"}, "1" => %{content: "No"}}
               }
             )
             |> render_submit()

    poll_block = Enum.find(Claper.Intro.get_event_page(event).blocks, &(&1.kind == "poll"))
    assert has_element?(pv, "#intro-block-#{poll_block.id}", "Have you been to a parole hearing?")
    assert has_element?(a, "#intro-block-#{poll_block.id} button", "Yes")

    # The phone answers, and changes its mind.
    a |> element("#intro-block-#{poll_block.id} button", "Yes") |> render_click()
    a |> element("#intro-block-#{poll_block.id} button", "No") |> render_click()

    assert a
           |> element("#intro-block-#{poll_block.id} button[aria-pressed=true]")
           |> render() =~ "No"

    page = Claper.Intro.get_event_page(event)

    assert [%{count: 1, summary: %{options: [%{count: 0}, %{count: 1}]}}] =
             Claper.Intro.results(page)

    # A form's editor offers the big-screen switch instead.
    {:ok, builder, html} = live(conn, "#{path}?add=form")
    assert html =~ "Show answers on the big screen"
    refute html =~ "Group answer"

    builder
    |> form("#form-form",
      form: %{title: "Your hopes", fields: %{"0" => %{name: "Hope", type: "text"}}},
      intro: %{show_answers: "true"}
    )
    |> render_submit()

    assert Enum.find(Claper.Intro.get_event_page(event).blocks, &(&1.kind == "form")).data ==
             %{"show_answers" => true}

    # After the start, answers are frozen.
    {:ok, manage, _} = live(conn, ~p"/e/#{event.code}/manage")
    manage |> element("#start-event-bar") |> render_click()
    render_hook(a, "intro_poll", %{"piece" => poll_block.id, "opt" => "999"})
    assert [%{count: 1} | _] = Claper.Intro.results(Claper.Intro.get_event_page(event))
  end

  test "the big screen shows live results beside the join column until the start", %{
    conn: conn,
    event: event
  } do
    page = Claper.Intro.get_event_page(event)
    {:ok, screen, _} = live(conn, ~p"/e/#{event.code}/presenter")
    refute has_element?(screen, "#join-results")

    {:ok, poll} =
      Claper.Intro.add_interaction(page, "poll", %{
        title: "Fair hearing?",
        poll_opts: [%{content: "Yes"}, %{content: "No"}]
      })

    {:ok, private} =
      Claper.Intro.add_interaction(page, "form", %{
        title: "Private thoughts",
        fields: [%{name: "Thought", type: "text"}]
      })

    {:ok, public} =
      Claper.Intro.add_interaction(
        page,
        "form",
        %{title: "Hopes", fields: [%{name: "Hope", type: "text"}]},
        %{"show_answers" => "true"}
      )

    Claper.Intro.broadcast_changed(Claper.Intro.get_event_page(event))
    assert has_element?(screen, ".join-screen.join-split")
    assert has_element?(screen, "#join-result-#{poll.id}", "Fair hearing?")

    a = phone(event, "phone-a")
    a |> element("#intro-block-#{poll.id} button", "Yes") |> render_click()
    assert has_element?(screen, "#join-result-#{poll.id}", "1 answer")

    for {block, text} <- [{private, "keep this to myself"}, {public, "to go home"}] do
      a
      |> form("#intro-block-#{block.id} form", %{
        piece: block.id,
        fields: %{"#{hd(Claper.Intro.load_content(block).fields).name}" => text}
      })
      |> render_change()
    end

    private_html = screen |> element("#join-result-#{private.id}") |> render()
    assert private_html =~ "1 person has answered"
    refute private_html =~ "keep this to myself"
    assert screen |> element("#join-result-#{public.id}") |> render() =~ "to go home"

    {:ok, manage, _} = live(conn, ~p"/e/#{event.code}/manage")
    manage |> element("#start-event-bar") |> render_click()
    refute has_element?(screen, "#join-results")
  end

  test "changes in the builder reach open phones", %{conn: conn, event: event} do
    a = phone(event, "phone-a")
    {:ok, builder, _} = live(conn, ~p"/e/#{event.code}/intro?add=heading")
    builder |> form("#block-form", block: %{text: "Doors open at six"}) |> render_submit()
    assert has_element?(a, "#intro h2", "Doors open at six")
  end

  test "the countdown runs to the scheduled start, then reads Starting soon", %{user: user} do
    later =
      NaiveDateTime.utc_now() |> NaiveDateTime.add(3 * 3600) |> NaiveDateTime.truncate(:second)

    future = event_fixture(%{user: user, started_at: later})
    pf = presentation_file_fixture(%{event: future})
    presentation_state_fixture(%{presentation_file: pf, started: false})
    a = phone(future, "phone-a")
    assert has_element?(a, "#intro .cd-row")
    refute has_element?(a, "#intro .intro-soon")

    past = event_fixture(%{user: user})
    pf = presentation_file_fixture(%{event: past})
    presentation_state_fixture(%{presentation_file: pf, started: false})
    b = phone(past, "phone-b")
    refute has_element?(b, "#intro .cd-row")
    assert has_element?(b, "#intro .intro-soon", "Starting soon")
  end
end
