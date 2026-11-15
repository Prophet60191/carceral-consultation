defmodule Claper.BreakoutsTest do
  use Claper.DataCase

  alias Claper.Breakouts
  alias Claper.Breakouts.{Packet, PieceType, Sorter}

  import Claper.{AccountsFixtures, PresentationsFixtures}

  describe "sorter" do
    test "largest group size: fewest groups, sizes within one" do
      assert Sorter.group_sizes(23, {:max_size, 5}) == [5, 5, 5, 4, 4]
      assert Sorter.group_sizes(12, {:max_size, 5}) == [4, 4, 4]
      assert Sorter.group_sizes(7, {:max_size, 5}) == [4, 3]
      assert Sorter.group_sizes(5, {:max_size, 5}) == [5]
      assert Sorter.group_sizes(6, {:max_size, 5}) == [3, 3]
      assert Sorter.group_sizes(1, {:max_size, 5}) == [1]
      assert Sorter.group_sizes(0, {:max_size, 5}) == []

      for n <- 1..60, max <- 2..12 do
        sizes = Sorter.group_sizes(n, {:max_size, max})
        assert Enum.sum(sizes) == n
        assert Enum.max(sizes) <= max
        assert Enum.max(sizes) - Enum.min(sizes) <= 1
        assert length(sizes) == div(n + max - 1, max)
      end
    end

    test "exact number of groups, never more groups than people" do
      assert Sorter.group_sizes(10, {:group_count, 3}) == [4, 3, 3]
      assert Sorter.group_sizes(2, {:group_count, 4}) == [1, 1]
    end

    test "deals everyone into groups, once each" do
      people = Enum.map(1..23, &"p#{&1}")
      groups = Sorter.assign(people, [5, 5, 5, 4, 4])
      assert Enum.map(groups, &length/1) == [5, 5, 5, 4, 4]
      assert groups |> List.flatten() |> Enum.sort() == Enum.sort(people)
    end

    test "packets are shared out in turn" do
      assert Enum.map(0..5, &Sorter.packet_for(&1, [:a, :b, :c])) == [:a, :b, :c, :a, :b, :c]
    end
  end

  defp event_breakout(attrs \\ %{}) do
    user = user_fixture()
    presentation_file = presentation_file_fixture()

    {:ok, breakout} =
      Breakouts.create_breakout(
        Map.merge(%{title: "Case review"}, attrs),
        %{user_id: user.id, presentation_file_id: presentation_file.id, position: 2}
      )

    %{breakout: breakout, user: user, presentation_file: presentation_file}
  end

  defp poll_piece(packet, piece_attrs \\ %{}, opts \\ ["Yes", "No"], multiple \\ false) do
    {:ok, piece} =
      Breakouts.add_piece(
        packet,
        Map.merge(%{kind: "poll"}, piece_attrs),
        %{
          title: "Should parole be granted?",
          multiple: multiple,
          poll_opts: Enum.map(opts, &%{content: &1})
        }
      )

    piece
  end

  defp option_ids(piece),
    do: piece |> Breakouts.load_content() |> Map.get(:poll_opts) |> Enum.map(& &1.id)

  describe "building" do
    test "a new breakout has one packet and is off" do
      %{breakout: breakout} = event_breakout()
      assert [%Packet{position: 0}] = breakout.packets
      refute breakout.enabled
      refute Claper.Breakouts.Breakout.library?(breakout)
    end

    test "settings are validated" do
      user = user_fixture()

      assert {:error, changeset} =
               Breakouts.create_breakout(%{title: "x", max_group_size: 1}, %{user_id: user.id})

      assert %{max_group_size: [_]} = errors_on(changeset)

      assert {:error, changeset} =
               Breakouts.create_breakout(%{title: "x", group_sizing: "group_count"}, %{
                 user_id: user.id
               })

      assert %{group_count: ["can't be blank"]} = errors_on(changeset)
    end

    test "only breakouts with different material per group get more than one case" do
      %{breakout: same} = event_breakout()
      assert {:error, :same_material} = Breakouts.add_packet(same, %{label: "B"})

      %{breakout: per_case} = event_breakout(%{material_mode: "per_case"})
      assert {:ok, %Packet{position: 1}} = Breakouts.add_packet(per_case, %{label: "Case B"})

      per_case = Breakouts.get_breakout!(per_case.id)

      assert {:error, changeset} = Breakouts.update_breakout(per_case, %{material_mode: "same"})
      assert %{material_mode: [_]} = errors_on(changeset)

      [first, second] = per_case.packets
      assert {:ok, _} = Breakouts.delete_packet(second)
      assert {:error, :last_packet} = Breakouts.delete_packet(first)
    end

    test "every interaction type can be a piece, and typed text needs text" do
      %{breakout: %{packets: [packet]}} = event_breakout()

      assert {:ok, text} =
               Breakouts.add_piece(packet, %{kind: "text", body: "Read the transcript."})

      assert Breakouts.load_content(text).body == "Read the transcript."
      assert {:error, changeset} = Breakouts.add_piece(packet, %{kind: "text"})
      assert %{body: ["can't be blank"]} = errors_on(changeset)

      poll = poll_piece(packet)
      assert length(option_ids(poll)) == 2

      assert {:ok, quiz} =
               Breakouts.add_piece(packet, %{kind: "quiz"}, %{
                 title: "Facts",
                 quiz_questions: [
                   %{
                     content: "Years served?",
                     quiz_question_opts: [
                       %{content: "19", is_correct: true},
                       %{content: "9", is_correct: false}
                     ]
                   }
                 ]
               })

      assert [_] = Breakouts.load_content(quiz).quiz_questions

      assert {:ok, _form} =
               Breakouts.add_piece(packet, %{kind: "form"}, %{
                 title: "Notes",
                 fields: [%{name: "Thoughts", type: "text"}]
               })

      assert {:ok, _cloud} =
               Breakouts.add_piece(packet, %{kind: "word_cloud"}, %{
                 title: "One word",
                 max_entries: 2
               })

      assert {:ok, embed} =
               Breakouts.add_piece(
                 packet,
                 %{kind: "embed", answer_scope: "group", visible_to_group: true},
                 %{
                   title: "Site",
                   provider: "website",
                   content: "https://example.com"
                 }
               )

      # Read-only pieces are never group answers or shared.
      assert embed.answer_scope == "individual"
      refute embed.visible_to_group

      assert {:error, _} = Breakouts.add_piece(packet, %{kind: "nope"})
      assert Enum.sort(PieceType.kinds()) == ~w(embed form poll quiz text word_cloud)
    end

    test "piece content never shows up as a slide interaction" do
      %{breakout: %{packets: [packet]}, presentation_file: pf} = event_breakout()
      piece = poll_piece(packet)
      poll = Breakouts.load_content(piece)

      assert Claper.Polls.get_poll_for_event(poll.id, pf.event_id) == nil
      assert Claper.Polls.list_polls(pf.id) == []
    end
  end

  describe "library and copies" do
    test "save to library, bring into another event, copy keeps content but not answers" do
      %{breakout: breakout, user: user} =
        event_breakout(%{material_mode: "per_case", timer_minutes: 15})

      [packet] = breakout.packets
      Breakouts.update_packet(packet, %{label: "Case A"})
      {:ok, _} = Breakouts.add_piece(packet, %{kind: "text", body: "Case A facts"})
      piece = poll_piece(packet, %{answer_scope: "group"})
      {:ok, _} = Breakouts.add_packet(breakout, %{label: "Case B"})

      {:ok, run} = Breakouts.start_run(breakout, ["a"])
      [group] = run.groups
      {:ok, _} = Breakouts.claim_note_taker(group, "a")
      {:ok, _} = Breakouts.put_answer(run, piece, "a", %{"options" => [hd(option_ids(piece))]})

      assert {:ok, library} = Breakouts.save_to_library(breakout, user.id)
      assert Claper.Breakouts.Breakout.library?(library)
      assert [%{id: id}] = Breakouts.list_library(user.id)
      assert id == library.id
      assert library.timer_minutes == 15
      assert Enum.map(library.packets, & &1.label) == ["Case A", "Case B"]
      [lib_a, _] = library.packets

      assert [
               %{kind: "text", body: "Case A facts"},
               %{kind: "poll", answer_scope: "group"} = lib_poll
             ] = lib_a.pieces

      assert lib_poll.id != piece.id
      assert length(option_ids(lib_poll)) == 2

      other = presentation_file_fixture()
      assert {:ok, copy} = Breakouts.copy_to_event(library, other.id, 4, user.id)
      assert copy.presentation_file_id == other.id
      assert copy.position == 4
      assert copy.source_breakout_id == library.id
      assert Breakouts.open_run(copy) == nil
      refute copy.enabled

      # Editing one copy never changes the other.
      {:ok, _} = Breakouts.update_breakout(copy, %{title: "Changed"})
      assert Breakouts.get_breakout!(library.id).title == "Case review"
    end

    test "duplicating an event copies its breakouts" do
      %{breakout: breakout, user: user, presentation_file: pf} = event_breakout()
      [packet] = breakout.packets
      poll_piece(packet)

      event = Claper.Repo.get!(Claper.Events.Event, pf.event_id)

      Claper.Repo.update_all(from(e in Claper.Events.Event, where: e.id == ^event.id),
        set: [user_id: user.id]
      )

      assert {:ok, copy} = Claper.Events.duplicate_event(user.id, event.uuid)
      copy = Claper.Repo.preload(copy, :presentation_file)
      assert [dup] = Breakouts.list_breakouts(copy.presentation_file.id)
      assert dup.position == breakout.position
      assert [%{pieces: [%{kind: "poll"}]}] = Breakouts.get_breakout!(dup.id).packets
    end
  end

  describe "running" do
    test "start sorts the connected people and shares packets out in turn" do
      %{breakout: breakout} = event_breakout(%{material_mode: "per_case", max_group_size: 3})
      {:ok, _} = Breakouts.add_packet(breakout, %{label: "B"})
      breakout = Breakouts.get_breakout!(breakout.id)
      [a, b] = breakout.packets

      people = Enum.map(1..10, &"p#{&1}")
      assert {:ok, run} = Breakouts.start_run(breakout, people ++ ["p1"], & &1)

      assert Enum.map(run.groups, &length(&1.members)) == [3, 3, 2, 2]
      assert Enum.map(run.groups, & &1.packet_id) == [a.id, b.id, a.id, b.id]
      assert run.ends_at == nil

      assert {:error, :already_running} = Breakouts.start_run(breakout, people)
      assert {:error, :nobody_connected} = Breakouts.start_run(breakout, [])
    end

    test "each person moves through their tasks one at a time" do
      %{breakout: breakout} = event_breakout()
      {:ok, run} = Breakouts.start_run(breakout, ["a"])
      member = Breakouts.membership(run, "a")
      assert member.step == 0

      assert {:ok, %{step: 2}} = Breakouts.set_step(member, 2, 2)
      assert {:error, :out_of_range} = Breakouts.set_step(member, 3, 2)
      assert {:error, :out_of_range} = Breakouts.set_step(member, -1, 2)
      assert Breakouts.membership(run, "a").step == 2
    end

    test "timer signals and can be extended" do
      %{breakout: breakout} = event_breakout(%{timer_minutes: 10})
      {:ok, run} = Breakouts.start_run(breakout, ["a"])
      assert DateTime.diff(run.ends_at, run.started_at) == 600

      {:ok, later} = Breakouts.add_time(run, 5)
      assert DateTime.diff(later.ends_at, run.ends_at) == 300

      {:ok, stopped} = Breakouts.stop_run(later)
      assert {:error, :stopped} = Breakouts.add_time(stopped, 5)
      assert {:error, :stopped} = Breakouts.stop_run(stopped)
    end

    test "note-takers volunteer: first wins, hand off reopens, outsiders cannot" do
      %{breakout: breakout} = event_breakout(%{max_group_size: 2})
      {:ok, run} = Breakouts.start_run(breakout, ["a", "b", "c", "d"], & &1)
      [g1, _g2] = run.groups

      assert {:ok, %{note_taker_identifier: "a"}} = Breakouts.claim_note_taker(g1, "a")
      assert {:error, :taken} = Breakouts.claim_note_taker(g1, "b")
      assert {:error, :not_in_group} = Breakouts.claim_note_taker(g1, "c")
      assert {:error, :not_note_taker} = Breakouts.hand_off_note_taker(g1, "b")
      assert {:ok, %{note_taker_identifier: nil}} = Breakouts.hand_off_note_taker(g1, "a")
      assert {:ok, %{note_taker_identifier: "b"}} = Breakouts.claim_note_taker(g1, "b")
      assert {:ok, %{note_taker_identifier: nil}} = Breakouts.clear_note_taker(g1)
    end

    test "reporting back shows one group of this run, or none" do
      %{breakout: breakout} = event_breakout()
      {:ok, run} = Breakouts.start_run(breakout, ["a"])
      [group] = run.groups
      assert {:ok, %{showing_group_id: id}} = Breakouts.show_group(run, group.id)
      assert id == group.id
      assert {:ok, %{showing_group_id: nil}} = Breakouts.show_group(run, nil)
      assert {:error, :unknown_group} = Breakouts.show_group(run, -1)
    end
  end

  describe "answers" do
    setup do
      %{breakout: breakout} = event_breakout(%{max_group_size: 2})
      [packet] = breakout.packets
      {:ok, text} = Breakouts.add_piece(packet, %{kind: "text", body: "Read"})
      mine = poll_piece(packet)
      shared = poll_piece(packet, %{visible_to_group: true})
      together = poll_piece(packet, %{answer_scope: "group"})
      {:ok, run} = Breakouts.start_run(breakout, ["a", "b", "c", "d"], & &1)
      %{run: run, text: text, mine: mine, shared: shared, together: together}
    end

    test "individual answers can be changed until the breakout stops", %{run: run, mine: mine} do
      [yes, no] = option_ids(mine)
      assert {:ok, _} = Breakouts.put_answer(run, mine, "a", %{"options" => [yes]})

      assert {:ok, answer} =
               Breakouts.put_answer(run, mine, "a", %{"options" => [Integer.to_string(no)]})

      assert answer.response == %{"options" => [no]}
      assert [_] = Breakouts.run_answers(run)

      assert {:error, "Choose one answer"} =
               Breakouts.put_answer(run, mine, "a", %{"options" => [yes, no]})

      assert {:error, "Unknown answer"} =
               Breakouts.put_answer(run, mine, "a", %{"options" => [-5]})

      assert {:error, :not_in_run} =
               Breakouts.put_answer(run, mine, "stranger", %{"options" => [yes]})

      {:ok, _} = Breakouts.stop_run(run)
      assert {:error, :stopped} = Breakouts.put_answer(run, mine, "a", %{"options" => [yes]})
    end

    test "group answers are written only by the note-taker", %{run: run, together: together} do
      [yes, no] = option_ids(together)
      [g1, _] = run.groups

      assert {:error, :not_note_taker} =
               Breakouts.put_answer(run, together, "a", %{"options" => [yes]})

      {:ok, _} = Breakouts.claim_note_taker(g1, "a")
      assert {:ok, _} = Breakouts.put_answer(run, together, "a", %{"options" => [yes]})

      # Hand-off: the new note-taker continues the same answer.
      {:ok, _} = Breakouts.hand_off_note_taker(g1, "a")
      {:ok, _} = Breakouts.claim_note_taker(g1, "b")

      assert {:ok, %{attendee_identifier: "b"}} =
               Breakouts.put_answer(run, together, "b", %{"options" => [no]})

      assert [%{scope: "group", response: %{"options" => [^no]}}] = Breakouts.run_answers(run)
    end

    test "read-only pieces and other groups' packets cannot be answered", %{run: run, text: text} do
      assert {:error, :not_answerable} = Breakouts.put_answer(run, text, "a", %{})

      %{breakout: other} = event_breakout()
      [other_packet] = other.packets
      foreign = poll_piece(other_packet)

      assert {:error, :not_your_packet} =
               Breakouts.put_answer(run, foreign, "a", %{"options" => option_ids(foreign)})
    end

    test "group-mates see shared answers, their group's answers and their own", %{
      run: run,
      mine: mine,
      shared: shared,
      together: together
    } do
      [g1, g2] = run.groups
      {:ok, _} = Breakouts.put_answer(run, mine, "b", %{"options" => [hd(option_ids(mine))]})
      {:ok, _} = Breakouts.put_answer(run, shared, "b", %{"options" => [hd(option_ids(shared))]})
      {:ok, _} = Breakouts.claim_note_taker(g1, "b")

      {:ok, _} =
        Breakouts.put_answer(run, together, "b", %{"options" => [hd(option_ids(together))]})

      {:ok, _} = Breakouts.put_answer(run, shared, "c", %{"options" => [hd(option_ids(shared))]})

      a = Breakouts.membership(run, "a")
      assert a.group_id == g1.id
      seen = Breakouts.visible_answers(run, a) |> Enum.map(&{&1.piece_id, &1.attendee_identifier})
      assert Enum.sort(seen) == Enum.sort([{shared.id, "b"}, {together.id, "b"}])

      b = Breakouts.membership(run, "b")
      assert length(Breakouts.visible_answers(run, b)) == 3

      c = Breakouts.membership(run, "c")
      assert c.group_id == g2.id
      assert [%{attendee_identifier: "c"}] = Breakouts.visible_answers(run, c)
    end

    test "results are summed up by group, per each piece's setting", %{
      run: run,
      mine: mine,
      together: together
    } do
      [yes, _no] = option_ids(mine)
      {:ok, _} = Breakouts.put_answer(run, mine, "a", %{"options" => [yes]})
      {:ok, _} = Breakouts.put_answer(run, mine, "b", %{"options" => [yes]})
      [g1, _] = run.groups
      {:ok, _} = Breakouts.claim_note_taker(g1, "a")

      {:ok, _} =
        Breakouts.put_answer(run, together, "a", %{"options" => [hd(option_ids(together))]})

      [r1, r2] = Breakouts.results(run)
      assert r1.group.number == 1

      mine_summary = Enum.find(r1.pieces, &(&1.piece.id == mine.id)).summary
      assert mine_summary.total == 2
      assert Enum.find(mine_summary.options, &(&1.id == yes)).count == 2

      assert Enum.find(r1.pieces, &(&1.piece.id == together.id)).summary.total == 1
      assert Enum.find(r2.pieces, &(&1.piece.id == mine.id)).summary.total == 0
      assert Enum.find(r1.pieces, &(&1.piece.kind == "text")).summary == %{}
    end
  end

  describe "live helpers" do
    test "answers can be taken back under the same rules, and only while running" do
      %{breakout: breakout} = event_breakout(%{max_group_size: 2})
      [packet] = breakout.packets
      mine = poll_piece(packet)
      together = poll_piece(packet, %{answer_scope: "group"})
      {:ok, run} = Breakouts.start_run(breakout, ["a", "b"], & &1)
      [group] = run.groups

      {:ok, _} = Breakouts.put_answer(run, mine, "a", %{"options" => [hd(option_ids(mine))]})
      assert {:ok, _} = Breakouts.withdraw_answer(run, mine, "a")
      assert Breakouts.run_answers(run) == []

      {:ok, _} = Breakouts.claim_note_taker(group, "a")

      {:ok, _} =
        Breakouts.put_answer(run, together, "a", %{"options" => [hd(option_ids(together))]})

      assert {:error, :not_note_taker} = Breakouts.withdraw_answer(run, together, "b")
      assert [_] = Breakouts.run_answers(run)

      {:ok, _} = Breakouts.stop_run(run)
      assert {:error, :stopped} = Breakouts.withdraw_answer(run, together, "a")
    end

    test "an absent note-taker is freed only if they still hold the role" do
      %{breakout: breakout} = event_breakout()
      {:ok, run} = Breakouts.start_run(breakout, ["a", "b"])
      [group] = run.groups
      {:ok, _} = Breakouts.claim_note_taker(group, "a")
      {:ok, _} = Breakouts.hand_off_note_taker(group, "a")
      {:ok, _} = Breakouts.claim_note_taker(group, "b")

      assert :unchanged = Breakouts.clear_note_taker_if(group, "a")
      assert {:ok, %{note_taker_identifier: nil}} = Breakouts.clear_note_taker_if(group, "b")
    end

    test "the breakout under way is found by its event, and marked running on its slide" do
      %{breakout: breakout, presentation_file: pf} = event_breakout()
      assert Breakouts.open_run_for_presentation(pf.id) == nil
      assert [%{running: false}] = Breakouts.list_breakouts_at_position(pf.id, 2)

      {:ok, run} = Breakouts.start_run(breakout, ["a"])
      assert Breakouts.open_run_for_presentation(pf.id).id == run.id
      assert [%{running: true}] = Breakouts.list_breakouts_at_position(pf.id, 2)

      assert Breakouts.event_uuid(breakout) ==
               Claper.Repo.get!(Claper.Events.Event, pf.event_id).uuid

      {:ok, _} = Breakouts.stop_run(run)
      assert Breakouts.open_run_for_presentation(pf.id) == nil
      assert Breakouts.latest_run(breakout).id == run.id
    end
  end

  describe "piece answers by type" do
    test "quiz, form and word cloud answers are cleaned and checked" do
      alias Claper.Breakouts.Pieces

      %{breakout: %{packets: [packet]}} = event_breakout()

      {:ok, quiz_piece} =
        Breakouts.add_piece(packet, %{kind: "quiz"}, %{
          title: "Facts",
          quiz_questions: [
            %{
              content: "Q1",
              quiz_question_opts: [
                %{content: "right", is_correct: true},
                %{content: "wrong", is_correct: false}
              ]
            },
            %{content: "Q2", quiz_question_opts: [%{content: "right", is_correct: true}]}
          ]
        })

      quiz = Breakouts.load_content(quiz_piece)
      [q1, q2] = quiz.quiz_questions
      [right, wrong] = Enum.map(q1.quiz_question_opts, & &1.id)

      assert {:ok, %{"answers" => answers}} =
               Pieces.Quiz.validate_response(quiz, %{
                 "answers" => %{"#{q1.id}" => [right], "#{q2.id}" => []}
               })

      assert answers == %{"#{q1.id}" => [right]}

      assert {:error, _} =
               Pieces.Quiz.validate_response(quiz, %{"answers" => %{"#{q2.id}" => [right]}})

      summary =
        Pieces.Quiz.summarize(quiz, [
          %{"answers" => answers},
          %{"answers" => %{"#{q1.id}" => [wrong]}}
        ])

      q1_summary = hd(summary.questions)
      assert q1_summary.answered == 2
      assert q1_summary.correct == 1

      {:ok, form_piece} =
        Breakouts.add_piece(packet, %{kind: "form"}, %{
          title: "Notes",
          fields: [%{name: "Thoughts", type: "text"}]
        })

      form = Breakouts.load_content(form_piece)

      assert {:ok, %{"fields" => %{"Thoughts" => "Fair"}}} =
               Pieces.Form.validate_response(form, %{"fields" => %{"Thoughts" => "  Fair "}})

      assert {:error, _} =
               Pieces.Form.validate_response(form, %{"fields" => %{"Thoughts" => "   "}})

      assert {:error, _} = Pieces.Form.validate_response(form, %{"fields" => %{"Other" => "x"}})

      {:ok, cloud_piece} =
        Breakouts.add_piece(packet, %{kind: "word_cloud"}, %{title: "One word", max_entries: 2})

      cloud = Breakouts.load_content(cloud_piece)

      assert {:ok, %{"words" => ["Fair"]}} =
               Pieces.WordCloud.validate_response(cloud, %{"words" => [" Fair ", "fair"]})

      assert {:error, "Too many words"} =
               Pieces.WordCloud.validate_response(cloud, %{"words" => ["a", "b", "c"]})

      assert %{words: [%{key: "fair", count: 2}]} =
               Pieces.WordCloud.summarize(cloud, [%{"words" => ["Fair"]}, %{"words" => ["fair"]}])
    end
  end
end
