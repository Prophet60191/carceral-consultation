defmodule ClaperWeb.BreakoutLiveTest do
  use ClaperWeb.ConnCase

  import Phoenix.LiveViewTest
  import Claper.{EventsFixtures, PresentationsFixtures}

  alias Claper.Breakouts

  setup :register_and_log_in_user

  defp own_event(user) do
    event = event_fixture(%{user: user})
    presentation_file = presentation_file_fixture(%{event: event})
    presentation_state_fixture(%{presentation_file: presentation_file, position: 3})
    %{event: event, presentation_file: presentation_file}
  end

  defp event_breakout(user, attrs \\ %{}) do
    %{event: event, presentation_file: pf} = own_event(user)

    {:ok, breakout} =
      Breakouts.create_breakout(
        Map.merge(%{title: "Case review"}, attrs),
        %{user_id: user.id, presentation_file_id: pf.id, position: 3}
      )

    %{event: event, breakout: breakout}
  end

  describe "creating" do
    test "a new breakout lands on the event's current slide and opens the builder", %{
      conn: conn,
      user: user
    } do
      %{event: event, presentation_file: pf} = own_event(user)
      {:ok, view, _html} = live(conn, ~p"/e/#{event.code}/breakouts/new")

      assert {:error, {:live_redirect, %{to: to}}} =
               view
               |> form("#breakout-new", breakout: %{title: "Hearing review"})
               |> render_submit()

      assert [breakout] = Breakouts.list_breakouts(pf.id)
      assert breakout.position == 3
      assert to == ~p"/e/#{event.code}/breakouts/#{breakout.id}"

      # It is listed with the slide's interactions, switched off.
      event = Claper.Events.get_event!(event.uuid, presentation_file: [])
      {:ok, interactions} = Claper.Interactions.get_interactions_at_position(event, 3)
      assert [%Claper.Breakouts.Breakout{enabled: false}] = interactions
    end

    test "an event breakout can start from the library", %{conn: conn, user: user} do
      {:ok, library} = Breakouts.create_breakout(%{title: "Saved one"}, %{user_id: user.id})
      %{event: event, presentation_file: pf} = own_event(user)

      {:ok, view, html} = live(conn, ~p"/e/#{event.code}/breakouts/new")
      assert html =~ "Saved one"

      assert {:error, {:live_redirect, _}} =
               view |> element("button[phx-value-id='#{library.id}']") |> render_click()

      assert [%{title: "Saved one", source_breakout_id: source}] = Breakouts.list_breakouts(pf.id)
      assert source == library.id
    end

    test "other people's events and libraries are out of reach", %{conn: conn} do
      stranger = Claper.AccountsFixtures.confirmed_user_fixture()
      %{event: event, breakout: breakout} = event_breakout(stranger)
      {:ok, library} = Breakouts.create_breakout(%{title: "Theirs"}, %{user_id: stranger.id})

      assert {:error, {:redirect, _}} = live(conn, ~p"/e/#{event.code}/breakouts/new")
      assert {:error, {:redirect, _}} = live(conn, ~p"/e/#{event.code}/breakouts/#{breakout.id}")
      assert {:error, {:redirect, _}} = live(conn, ~p"/breakouts/#{library.id}")
    end
  end

  describe "building" do
    test "settings save as they change and show errors", %{conn: conn, user: user} do
      %{event: event, breakout: breakout} = event_breakout(user)
      {:ok, view, _html} = live(conn, ~p"/e/#{event.code}/breakouts/#{breakout.id}")

      view
      |> form("#breakout-settings", breakout: %{max_group_size: "4", timer_minutes: "12"})
      |> render_change()

      saved = Breakouts.get_breakout!(breakout.id)
      assert saved.max_group_size == 4
      assert saved.timer_minutes == 12

      html =
        view |> form("#breakout-settings", breakout: %{max_group_size: "40"}) |> render_change()

      assert html =~ "must be less than or equal to 12"
      assert Breakouts.get_breakout!(breakout.id).max_group_size == 4
    end

    test "typed text and interaction pieces are added, set, moved and removed", %{
      conn: conn,
      user: user
    } do
      %{event: event, breakout: breakout} = event_breakout(user)
      [packet] = breakout.packets
      path = ~p"/e/#{event.code}/breakouts/#{breakout.id}"
      {:ok, view, _html} = live(conn, path)

      # Typed text
      view |> element("a", "Text") |> render_click()
      assert render(view) =~ "Text to read"
      view |> form("#text-editor", %{body: ""}) |> render_submit()
      assert render(view) =~ "Write some text first"
      view |> form("#text-editor", %{body: "Read the board's decision."}) |> render_submit()
      assert_patch(view, path)

      # A poll, with the poll editor in piece mode (no slide-only options),
      # ticked as a group answer
      {:ok, view, html} = live(conn, "#{path}?add=poll&packet=#{packet.id}")
      refute html =~ "Show the results on phones"
      refute html =~ "Show the results on the big screen"
      assert html =~ "Multiple answers"
      assert html =~ "Group answer"

      assert {:error, {:live_redirect, %{to: ^path}}} =
               view
               |> form("#poll-form",
                 poll: %{
                   title: "Should parole be granted?",
                   poll_opts: %{"0" => %{content: "Yes"}, "1" => %{content: "No"}}
                 },
                 breakout: %{group_answer: "true"}
               )
               |> render_submit()

      [text, poll] = Breakouts.get_breakout!(breakout.id).packets |> hd() |> Map.get(:pieces)
      assert text.kind == "text"
      assert poll.kind == "poll"
      assert poll.answer_scope == "group"
      assert Breakouts.load_content(poll).title == "Should parole be granted?"

      {:ok, _view, html} = live(conn, path)
      assert html =~ "Read the board&#39;s decision."
      assert html =~ "Should parole be granted?"
      assert html =~ "Group answer · note-taker"

      # Editing: the box shows the saved choice; unticked, each person answers
      {:ok, view, _html} = live(conn, "#{path}?edit=#{poll.id}")

      assert view |> element("input[type=checkbox][name='breakout[group_answer]']") |> render() =~
               "checked"

      assert {:error, {:live_redirect, _}} =
               view
               |> form("#poll-form",
                 poll: %{title: "Grant parole?"},
                 breakout: %{group_answer: "false"}
               )
               |> render_submit()

      assert Breakouts.load_content(poll).title == "Grant parole?"

      poll =
        Breakouts.get_breakout!(breakout.id).packets |> hd() |> Map.get(:pieces) |> List.last()

      assert poll.answer_scope == "individual"

      # Whether the group sees each person's answers
      {:ok, view, html} = live(conn, path)
      assert html =~ "Each person answers"
      view |> element("#piece-#{poll.id} button[role=switch]") |> render_click()

      assert Breakouts.get_breakout!(breakout.id).packets
             |> hd()
             |> Map.get(:pieces)
             |> List.last()
             |> Map.get(:visible_to_group)

      # Reorder and remove
      view |> element("#piece-#{poll.id} button[phx-value-dir=up]") |> render_click()

      assert [%{kind: "poll"}, %{kind: "text"}] =
               Breakouts.get_breakout!(breakout.id).packets |> hd() |> Map.get(:pieces)

      view |> element("#piece-#{text.id} button[phx-click=delete_piece]") |> render_click()

      assert [%{kind: "poll"}] =
               Breakouts.get_breakout!(breakout.id).packets |> hd() |> Map.get(:pieces)
    end

    test "a quiz can be created in a breakout (its button isn't stuck greyed out)", %{
      conn: conn,
      user: user
    } do
      {:ok, breakout} =
        Breakouts.create_breakout(%{title: "Quiz check"}, %{user_id: user.id})

      [packet] = breakout.packets
      path = ~p"/breakouts/#{breakout.id}"
      {:ok, view, _html} = live(conn, "#{path}?add=quiz&packet=#{packet.id}")

      quiz = %{
        title: "Board knowledge",
        quiz_questions: %{
          "0" => %{
            content: "Who decides parole in New York?",
            quiz_question_opts: %{
              "0" => %{content: "The Board of Parole", is_correct: "true"},
              "1" => %{content: "The judge", is_correct: "false"}
            }
          }
        }
      }

      view |> form("#form-quiz", quiz: quiz) |> render_change()
      assert has_element?(view, "#form-quiz button[type=submit]")
      refute has_element?(view, "#form-quiz button[type=submit][disabled]")

      assert {:error, {:live_redirect, %{to: ^path}}} =
               view |> form("#form-quiz", quiz: quiz) |> render_submit()

      [piece] = Breakouts.get_breakout!(breakout.id).packets |> hd() |> Map.get(:pieces)
      assert piece.kind == "quiz"
      content = Breakouts.load_content(piece)
      assert content.title == "Board knowledge"
      assert [%{quiz_question_opts: [_, _]}] = content.quiz_questions
    end

    test "different material per group: sets are added and removed, with no names", %{
      conn: conn,
      user: user
    } do
      %{event: event, breakout: breakout} = event_breakout(user, %{material_mode: "per_case"})
      {:ok, view, html} = live(conn, ~p"/e/#{event.code}/breakouts/#{breakout.id}")
      refute html =~ ~r/Case [A-Z]\b|Case name|Add a case|Remove case/

      view |> element("button", "Add material for another group") |> render_click()
      [a, b] = Breakouts.get_breakout!(breakout.id).packets

      html = render(view)
      assert html =~ "1 of 2"
      assert html =~ "2 of 2"
      refute html =~ ~r/Case [A-Z]\b|Case name|Add a case|Remove case/
      refute has_element?(view, "#packet-#{b.id} input[name=label]")

      view |> element("#packet-#{a.id} button", "Remove") |> render_click()
      assert [%{id: id}] = Breakouts.get_breakout!(breakout.id).packets
      assert id == b.id
    end

    test "save to library and delete", %{conn: conn, user: user} do
      %{event: event, breakout: breakout} = event_breakout(user)
      {:ok, view, _html} = live(conn, ~p"/e/#{event.code}/breakouts/#{breakout.id}")

      view |> element("button", "Save a copy to your library") |> render_click()
      assert [%{title: "Case review"}] = Breakouts.list_library(user.id)

      assert {:error, {:live_redirect, %{to: to}}} =
               view |> element("button", "Delete breakout") |> render_click()

      assert to == ~p"/e/#{event.code}/manage"
      assert Breakouts.list_breakouts(breakout.presentation_file_id) == []
    end
  end

  describe "library" do
    test "lists, creates and deletes library breakouts", %{conn: conn, user: user} do
      {:ok, _view, html} = live(conn, ~p"/breakouts")
      assert html =~ "Nothing saved yet"

      {:ok, new_view, _html} = live(conn, ~p"/breakouts/new")

      assert {:error, {:live_redirect, %{to: to}}} =
               new_view
               |> form("#breakout-new", breakout: %{title: "Jigsaw cases"})
               |> render_submit()

      [saved] = Breakouts.list_library(user.id)
      assert to == ~p"/breakouts/#{saved.id}"

      {:ok, view, html} = live(conn, ~p"/breakouts")
      assert html =~ "Jigsaw cases"

      view |> element("#library-#{saved.id} button[phx-click=delete]") |> render_click()
      assert Breakouts.list_library(user.id) == []
      _ = view
    end
  end
end
