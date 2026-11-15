defmodule ClaperWeb.BreakoutExportTest do
  @moduledoc "Breakout results after the session (docs/BREAKOUT.md, step 6)."
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
      Breakouts.create_breakout(%{title: "Case review", material_mode: "per_case"}, %{
        user_id: user.id,
        presentation_file_id: pf.id,
        position: 0
      })

    [packet] = breakout.packets
    {:ok, _} = Breakouts.update_packet(packet, %{label: "Case A: 26 years"})
    {:ok, _} = Breakouts.add_piece(packet, %{kind: "text", body: "Read."})

    {:ok, poll} =
      Breakouts.add_piece(packet, %{kind: "poll", answer_scope: "group"}, %{
        title: "Grant parole?",
        poll_opts: [%{content: "Grant"}, %{content: "Deny"}]
      })

    {:ok, form} =
      Breakouts.add_piece(packet, %{kind: "form"}, %{
        title: "Arguments",
        fields: [%{name: "Strongest point", type: "text"}]
      })

    {:ok, run} = Breakouts.start_run(breakout, ["a", "b"])
    [group] = run.groups
    {:ok, _} = Breakouts.claim_note_taker(group, "a")
    grant = poll |> Breakouts.load_content() |> Map.get(:poll_opts) |> hd() |> Map.get(:id)
    {:ok, _} = Breakouts.put_answer(run, poll, "a", %{"options" => [grant]})

    {:ok, _} =
      Breakouts.put_answer(run, form, "b", %{
        "fields" => %{"Strongest point" => "His record, line one\nline two"}
      })

    {:ok, run} = Breakouts.stop_run(run)

    %{event: event, run: run}
  end

  test "a run exports one row per answer, by group", %{conn: conn, run: run} do
    conn = post(conn, ~p"/export/breakouts/runs/#{run.id}")
    assert response_content_type(conn, :csv)
    assert get_resp_header(conn, "content-disposition") |> hd() =~ "breakout-"

    [header | rows] = [conn.resp_body] |> CSV.decode!(headers: false) |> Enum.to_list()
    assert header == Claper.Breakouts.Export.headers()
    assert length(rows) == 2

    [group_row, person_row] = rows
    assert Enum.at(group_row, 0) == "Case review"
    assert Enum.at(group_row, 3) == "1"
    assert Enum.at(group_row, 5) == "Poll"
    assert Enum.at(group_row, 7) == "Group (note-taker)"
    assert Enum.at(group_row, 9) == "Grant"
    # Material has no name (decision 25): no column for it.
    refute "Case" in header

    assert Enum.at(person_row, 7) == Base.encode16("b")
    assert Enum.at(person_row, 8) == "Strongest point"
    assert Enum.at(person_row, 9) == "His record, line one\nline two"
  end

  test "other people cannot export someone else's breakout", %{run: run} do
    stranger = Claper.AccountsFixtures.confirmed_user_fixture()
    conn = build_conn() |> log_in_user(stranger) |> post(~p"/export/breakouts/runs/#{run.id}")
    assert conn.status == 403

    conn = build_conn() |> log_in_user(stranger) |> post(~p"/export/breakouts/runs/999999")
    assert conn.status == 404
  end

  test "the stats page has a Breakouts tab with each run and group", %{
    conn: conn,
    event: event,
    run: run
  } do
    {:ok, view, _html} = live(conn, ~p"/events/#{event.uuid}/stats")
    html = view |> element("[phx-value-tab=breakouts]") |> render_click()
    assert html =~ "Case review"
    assert html =~ "Group 1"
    refute html =~ "Case A: 26 years"
    assert html =~ "Grant parole?"
    assert html =~ "His record, line one"
    assert html =~ "/export/breakouts/runs/#{run.id}"
  end
end
