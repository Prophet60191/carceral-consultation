defmodule ClaperWeb.EventLive.ResultsOnScreenTest do
  @moduledoc """
  "Show the results on the big screen", chosen per interaction in its editor
  (Jose, 2026-11-14): turning the interaction on starts the big screen from
  that choice; the manage screen's switch changes only the current run.
  """
  use ClaperWeb.ConnCase

  import Phoenix.LiveViewTest
  import Claper.{FormsFixtures, PollsFixtures, PresentationsFixtures, QuizzesFixtures}

  alias Claper.{Forms, Polls, Presentations, Quizzes}

  setup [:register_and_log_in_user]

  setup %{user: user} do
    presentation_file = presentation_file_fixture(%{user: user, length: 2}, [:event])
    presentation_state_fixture(%{presentation_file: presentation_file, poll_visible: false})
    %{presentation_file: presentation_file, event: presentation_file.event}
  end

  @toggle ~s(#settings-modal-content button[phx-value-key="poll_visible"][phx-key="Z"])

  test "a poll ticked for the big screen shows its results as soon as it is on", %{
    conn: conn,
    presentation_file: pf,
    event: event
  } do
    poll =
      poll_fixture(%{
        presentation_file_id: pf.id,
        title: "Fair hearing?",
        enabled: false,
        results_on_screen: true
      })

    {:ok, manager, _} = live(conn, ~p"/e/#{event.code}/manage")
    {:ok, screen, _} = live(conn, ~p"/e/#{event.code}/presenter")

    render_hook(manager, "poll-set-active", %{"id" => to_string(poll.id)})
    assert state(pf).poll_visible
    assert has_element?(screen, "#poll.opacity-100", "Fair hearing?")
    assert has_element?(manager, @toggle <> ~s([aria-checked="true"]))

    # Switching it off on the manage screen hides it for this run only.
    manager |> element(@toggle) |> render_keydown()
    refute state(pf).poll_visible
    assert has_element?(screen, "#poll.opacity-0")
    assert Polls.get_poll!(poll.id).results_on_screen

    # Turned on again later, it follows the plan again.
    render_hook(manager, "poll-set-inactive", %{"id" => to_string(poll.id)})
    render_hook(manager, "poll-set-active", %{"id" => to_string(poll.id)})
    assert state(pf).poll_visible
  end

  test "an unticked poll keeps the slide on the big screen, even after one that showed", %{
    conn: conn,
    presentation_file: pf,
    event: event
  } do
    {:ok, _} = Presentations.update_presentation_state(state(pf), %{poll_visible: true})
    poll = poll_fixture(%{presentation_file_id: pf.id, enabled: false})
    refute poll.results_on_screen

    {:ok, manager, _} = live(conn, ~p"/e/#{event.code}/manage")
    {:ok, screen, _} = live(conn, ~p"/e/#{event.code}/presenter")

    render_hook(manager, "poll-set-active", %{"id" => to_string(poll.id)})
    refute state(pf).poll_visible
    assert has_element?(screen, "#poll.opacity-0")
  end

  test "a quiz's reveal starts from its choice", %{
    conn: conn,
    presentation_file: pf,
    event: event
  } do
    shown = quiz_fixture(%{presentation_file: pf, position: 0, results_on_screen: true})
    hidden = quiz_fixture(%{presentation_file: pf, position: 0, show_results: true})

    {:ok, manager, _} = live(conn, ~p"/e/#{event.code}/manage")

    render_hook(manager, "quiz-set-active", %{"id" => to_string(shown.id)})
    assert Quizzes.get_quiz!(shown.id).show_results

    render_hook(manager, "quiz-set-active", %{"id" => to_string(hidden.id)})
    refute Quizzes.get_quiz!(hidden.id).show_results
    refute Quizzes.get_quiz!(hidden.id).results_on_screen
  end

  test "a form ticked for the big screen shows what people write, live and without names", %{
    conn: conn,
    presentation_file: pf,
    event: event
  } do
    form =
      form_fixture(%{
        presentation_file_id: pf.id,
        title: "One word for today",
        enabled: false,
        results_on_screen: true
      })

    {:ok, _} =
      Forms.create_or_update_form_submit(event.uuid, %{
        "attendee_identifier" => "phone-a",
        "form_id" => form.id,
        "response" => %{"Name" => "Hopeful"}
      })

    {:ok, manager, _} = live(conn, ~p"/e/#{event.code}/manage")
    {:ok, screen, _} = live(conn, ~p"/e/#{event.code}/presenter")

    render_hook(manager, "form-set-active", %{"id" => to_string(form.id)})
    assert state(pf).poll_visible
    assert has_element?(screen, "#form-answers.opacity-100", "One word for today")
    assert has_element?(screen, "#form-answers", "Hopeful")
    assert has_element?(screen, "#form-answers", "1 answer")
    assert has_element?(manager, @toggle <> ~s([aria-checked="true"]))
    assert render(manager) =~ "Show answers on big screen"

    {:ok, _} =
      Forms.create_or_update_form_submit(event.uuid, %{
        "attendee_identifier" => "phone-b",
        "form_id" => form.id,
        "response" => %{"Name" => "Tired"}
      })

    assert has_element?(screen, "#form-answers", "Tired")
    assert has_element?(screen, "#form-answers", "2 answers")
    refute render(screen) =~ "phone-a"
  end

  test "the editor offers the choice and saves it", %{
    conn: conn,
    presentation_file: pf,
    event: event
  } do
    poll = poll_fixture(%{presentation_file_id: pf.id, enabled: false})
    {:ok, editor, _} = live(conn, ~p"/e/#{event.code}/manage/edit/poll/#{poll.id}")

    assert render(editor) =~ "Show the results on the big screen"
    assert render(editor) =~ "Show the results on phones"

    editor
    |> form("#poll-form", poll: %{results_on_screen: "true"})
    |> render_submit()

    assert Polls.get_poll!(poll.id).results_on_screen
  end

  defp state(pf),
    do: Presentations.get_presentation_file!(pf.id, [:presentation_state]).presentation_state
end
