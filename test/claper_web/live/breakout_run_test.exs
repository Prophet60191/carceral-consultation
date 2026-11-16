defmodule ClaperWeb.BreakoutRunTest do
  @moduledoc """
  Running a breakout end to end (docs/BREAKOUT.md, steps 4–5): the
  presenter's live page, phones in the room, the big screen.
  """
  use ClaperWeb.ConnCase

  import Phoenix.LiveViewTest
  import Claper.{EventsFixtures, PresentationsFixtures}

  alias Claper.Breakouts

  setup :register_and_log_in_user

  setup %{user: user} do
    event = event_fixture(%{user: user})
    pf = presentation_file_fixture(%{event: event})
    presentation_state_fixture(%{presentation_file: pf})

    {:ok, breakout} =
      Breakouts.create_breakout(%{title: "Case review", timer_minutes: 10}, %{
        user_id: user.id,
        presentation_file_id: pf.id,
        position: 0
      })

    [packet] = breakout.packets
    {:ok, _} = Breakouts.add_piece(packet, %{kind: "text", body: "Read the decision."})

    {:ok, own} =
      Breakouts.add_piece(packet, %{kind: "poll", visible_to_group: true}, %{
        title: "Fair hearing?",
        poll_opts: [%{content: "Yes"}, %{content: "No"}]
      })

    {:ok, shared} =
      Breakouts.add_piece(packet, %{kind: "poll", answer_scope: "group"}, %{
        title: "Group verdict",
        poll_opts: [%{content: "Grant"}, %{content: "Deny"}]
      })

    %{event: event, breakout: breakout, own: own, shared: shared}
  end

  defp phone(event, identifier) do
    conn =
      Phoenix.ConnTest.build_conn()
      |> Plug.Test.init_test_session(%{attendee_identifier: identifier})

    {:ok, view, _html} = live(conn, ~p"/e/#{event.code}")
    view
  end

  defp opt_id(piece, content) do
    piece
    |> Breakouts.load_content()
    |> Map.get(:poll_opts)
    |> Enum.find(&(&1.content == content))
    |> Map.get(:id)
  end

  test "a breakout runs from start to stop",
       %{conn: conn, event: event, breakout: breakout} = ctx do
    a = phone(event, "phone-a")
    b = phone(event, "phone-b")
    refute has_element?(a, "#breakout-phone")

    {:ok, control, html} = live(conn, ~p"/e/#{event.code}/breakouts/#{breakout.id}/live")
    assert html =~ "2 people connected → 1 group: 2"

    {:ok, screen, _} = live(conn, ~p"/e/#{event.code}/presenter")
    refute has_element?(screen, "#breakout-screen")

    # Start: phones switch to their group on task 1 of 3; the big screen
    # shows the timer.
    control |> element("button", "Start breakout") |> render_click()
    assert has_element?(a, "#breakout-phone", "Group 1")
    assert has_element?(a, "#bk-progress", "This breakout has 3 tasks")
    assert has_element?(a, "#bk-progress", "Task 1 of 3")
    assert has_element?(b, "#breakout-phone", "Read the decision.")
    refute has_element?(b, "#bk-piece-#{ctx.own.id}")
    assert has_element?(screen, "#breakout-screen", "Case review")
    assert has_element?(screen, "#bk-screen-timer")
    assert render(control) =~ "No note-taker yet"

    # One task at a time: no answering ahead.
    render_hook(a, "bk_poll", %{"piece" => ctx.own.id, "opt" => opt_id(ctx.own, "Yes")})
    run = Breakouts.open_run(breakout)
    assert Breakouts.run_answers(run) == []

    # Each person moves on alone.
    a |> element("button", "Done reading") |> render_click()
    assert has_element?(a, "#bk-progress", "Task 2 of 3")
    assert has_element?(b, "#bk-progress", "Task 1 of 3")
    b |> element("button", "Done reading") |> render_click()

    # Individual answers, shared with the group on this piece.
    a |> element("#bk-piece-#{ctx.own.id} button", "Yes") |> render_click()
    b |> element("#bk-piece-#{ctx.own.id} button", "No") |> render_click()
    assert render(a) =~ "Your group&#39;s answers"
    assert render(control) =~ "2/2"

    # Changing an answer before the stop.
    b |> element("#bk-piece-#{ctx.own.id} button", "Yes") |> render_click()
    yes = opt_id(ctx.own, "Yes")

    assert %{response: %{"options" => [^yes]}} =
             Enum.find(
               Breakouts.run_answers(run),
               &(&1.attendee_identifier == "phone-b" and &1.piece_id == ctx.own.id)
             )

    # The group answer asks for a note-taker on the task itself.
    a |> element("button", "Next") |> render_click()
    assert has_element?(a, "#bk-note-taker-#{ctx.shared.id}", "Someone needs to take notes")
    a |> element("#bk-note-taker-#{ctx.shared.id} button", "I'll take notes") |> render_click()
    assert render(a) =~ "You&#39;re writing this answer for Group 1."
    assert render(control) =~ "Has a note-taker"

    # B arrives at it later: only the note-taker writes it.
    b |> element("button", "Next") |> render_click()
    assert has_element?(b, "#bk-note-taker-#{ctx.shared.id}", "Your note-taker writes")
    assert b |> element("#bk-piece-#{ctx.shared.id} button", "Deny") |> render() =~ "disabled"

    assert render_hook(b, "bk_poll", %{
             "piece" => ctx.shared.id,
             "opt" => opt_id(ctx.shared, "Deny")
           }) =~
             "Only your group&#39;s note-taker can answer this one"

    a |> element("#bk-piece-#{ctx.shared.id} button", "Grant") |> render_click()

    assert b
           |> element("#bk-piece-#{ctx.shared.id} button[aria-pressed=true]")
           |> render() =~ "Grant"

    # Finishing, then going back to check.
    a |> element("button", "Finish") |> render_click()
    assert render(a) =~ "You&#39;ve finished every task."
    a |> element("button", "Back") |> render_click()
    assert has_element?(a, "#bk-progress", "Task 3 of 3")

    # A message to every group.
    control
    |> form("#bk-message", message: %{text: "Five minutes left", group: ""})
    |> render_submit()

    assert render(a) =~ "Five minutes left"
    assert render(b) =~ "Five minutes left"

    # Adding time moves the timer.
    before = run.ends_at
    control |> element("button", "+5 min") |> render_click()
    assert DateTime.diff(Breakouts.open_run(breakout).ends_at, before) == 300

    # Groups are locked: someone arriving now is sent to the presenter.
    c = phone(event, "phone-c")
    refute has_element?(c, "#breakout-phone")
    assert has_element?(c, "#breakout-outside", "See the presenter to be assigned to a group.")
    assert Breakouts.membership(run, "phone-c") == nil

    # Reporting back: the group on the big screen only; phones keep their
    # own group's work (Jose, 2026-11-15).
    group = hd(Breakouts.open_run(breakout).groups)

    # The card names its group once; its Answers section doesn't repeat it.
    card = control |> element("#bk-group-#{group.id}") |> render()
    assert length(String.split(card, "Group 1")) == 2

    control |> element("#bk-group-#{group.id} button", "Show on big screen") |> render_click()
    assert has_element?(screen, "#breakout-screen", "Reporting back")
    assert render(screen) =~ "Group verdict"
    refute render(b) =~ "Reporting back"
    assert has_element?(b, "#breakout-phone")

    # Stop: answers are final, phones and the big screen return to the slides.
    control |> element("button", "Stop breakout") |> render_click()
    refute has_element?(a, "#breakout-phone")
    refute has_element?(c, "#breakout-outside")
    refute has_element?(screen, "#breakout-screen")
    assert render(control) =~ "Last run, stopped"

    assert {:error, :stopped} =
             Breakouts.put_answer(run, ctx.own, "phone-a", %{"options" => [yes]})
  end

  test "a breakout with one task has no steps", %{
    conn: conn,
    event: event,
    breakout: breakout,
    own: own
  } do
    [packet] = Breakouts.get_breakout!(breakout.id).packets
    for piece <- packet.pieces, piece.id != own.id, do: {:ok, _} = Breakouts.delete_piece(piece)

    a = phone(event, "phone-a")
    {:ok, control, _} = live(conn, ~p"/e/#{event.code}/breakouts/#{breakout.id}/live")
    control |> element("button", "Start breakout") |> render_click()

    assert has_element?(a, "#bk-piece-#{own.id}", "Fair hearing?")
    refute has_element?(a, "#bk-progress")
    refute has_element?(a, "button[phx-click=bk_next]")
    refute has_element?(a, "button[phx-click=bk_back]")
  end

  test "the manage screen offers Start, then Live while it runs", %{
    conn: conn,
    event: event,
    breakout: breakout
  } do
    _a = phone(event, "phone-a")
    {:ok, manage, _} = live(conn, ~p"/e/#{event.code}/manage")
    assert manage |> element("a[href$='/breakouts/#{breakout.id}/live']") |> render() =~ "Start"

    {:ok, _run} = Claper.Breakouts.Live.start(breakout, ["phone-a"])
    assert manage |> element("a[href$='/breakouts/#{breakout.id}/live']") |> render() =~ "Live"
  end

  test "nobody connected: start is refused with a clear note", %{
    conn: conn,
    event: event,
    breakout: breakout
  } do
    {:ok, control, html} = live(conn, ~p"/e/#{event.code}/breakouts/#{breakout.id}/live")
    assert html =~ "Nobody is connected yet."
    assert control |> element("button", "Start breakout") |> render() =~ "disabled"
  end

  test "no group answer, no note-taker: nobody is asked", %{
    conn: conn,
    event: event,
    breakout: breakout,
    shared: shared
  } do
    {:ok, _} = Breakouts.delete_piece(shared)
    a = phone(event, "phone-a")
    {:ok, control, _} = live(conn, ~p"/e/#{event.code}/breakouts/#{breakout.id}/live")
    control |> element("button", "Start breakout") |> render_click()

    a |> element("button", "Done reading") |> render_click()
    assert has_element?(a, "#breakout-phone", "Fair hearing?")
    refute render(a) =~ "note-taker"
    refute render(a) =~ "I&#39;ll take notes"
    refute render(control) =~ "note-taker"
  end

  test "a note-taker gone for good frees the role", %{event: event, breakout: breakout} do
    {:ok, run} = Claper.Breakouts.Live.start(breakout, ["phone-a", "phone-b"])
    [group] = run.groups
    {:ok, _} = Breakouts.claim_note_taker(group, "phone-a")

    # B is on the group answer (task 3 of 3).
    {:ok, _} = Breakouts.set_step(Breakouts.membership(run, "phone-b"), 2, 3)
    b = phone(event, "phone-b")
    # phone-a is not connected: B's phone checks after the grace period.
    send(b.pid, {:bk_check_note_taker, group.id, "phone-a"})
    assert render(b) =~ "I&#39;ll take notes"
    assert Breakouts.get_run!(run.id).groups |> hd() |> Map.get(:note_taker_identifier) == nil
  end
end
