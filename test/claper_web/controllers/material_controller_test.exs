defmodule ClaperWeb.MaterialControllerTest do
  use ClaperWeb.ConnCase, async: false

  import Claper.EventsFixtures
  import Claper.PresentationsFixtures
  import Claper.AccountsFixtures

  alias Claper.Materials

  @pdf "%PDF-1.4\n%%EOF\n"

  defp minutes(n),
    do: NaiveDateTime.add(NaiveDateTime.utc_now(), n * 60) |> NaiveDateTime.truncate(:second)

  defp add(event, kind, title) do
    path = Path.join(System.tmp_dir!(), "mc-#{System.unique_integer([:positive])}.pdf")
    File.write!(path, @pdf)
    on_exit(fn -> File.rm(path) end)
    {:ok, [m]} = Materials.create_material(event, %{kind: kind, title: title}, path)
    m
  end

  setup do
    owner = user_fixture()
    event = event_fixture(%{user: owner, expired_at: nil})
    on_exit(fn -> Materials.delete_event_files(event) end)
    %{owner: owner, event: event}
  end

  test "a handout while the event runs, as a download", %{conn: conn, event: event} do
    m = add(event, "handout", "Sample letter: é")
    conn = get(conn, ~p"/materials/#{m.uuid}?download=1")

    assert response(conn, 200) == @pdf
    assert get_resp_header(conn, "content-type") == ["application/pdf"]
    assert [disposition] = get_resp_header(conn, "content-disposition")
    assert disposition =~ ~s(attachment; filename="Sample letter e.pdf")
    assert disposition =~ "filename*=UTF-8''Sample%20letter%3A%20%C3%A9.pdf"
    assert get_resp_header(conn, "x-content-type-options") == ["nosniff"]
    assert Claper.Repo.get!(Materials.Material, m.id).downloads == 1
  end

  test "viewing doesn't count as a download", %{conn: conn, event: event} do
    m = add(event, "handout", "Worksheet")
    assert response(get(conn, ~p"/materials/#{m.uuid}"), 200)
    assert Claper.Repo.get!(Materials.Material, m.id).downloads == 0
  end

  test "nothing switched off, nothing take-home before the end", %{conn: conn, event: event} do
    off = add(event, "handout", "Off")
    {:ok, _} = Materials.set_enabled(off, false)
    take_home = add(event, "take_home", "Later")

    assert response(get(conn, ~p"/materials/#{off.uuid}"), 404)
    assert response(get(conn, ~p"/materials/#{take_home.uuid}"), 404)
    assert response(get(conn, ~p"/materials/not-a-uuid"), 404)
    assert response(get(conn, ~p"/materials/#{Ecto.UUID.generate()}"), 404)
  end

  test "after the end: take-home until it closes, handouts no longer", %{
    conn: conn,
    event: event
  } do
    handout = add(event, "handout", "Worksheet")
    take_home = add(event, "take_home", "Guide")

    {:ok, event} =
      event |> Ecto.Changeset.change(expired_at: minutes(-1)) |> Claper.Repo.update()

    assert response(get(conn, ~p"/materials/#{take_home.uuid}"), 200)
    assert response(get(conn, ~p"/materials/#{handout.uuid}"), 404)

    {:ok, _} = event |> Ecto.Changeset.change(take_home_until: minutes(0)) |> Claper.Repo.update()
    assert response(get(conn, ~p"/materials/#{take_home.uuid}"), 404)
  end

  test "the people who run the event always get their files", %{
    conn: conn,
    owner: owner,
    event: event
  } do
    off = add(event, "take_home", "Draft")
    {:ok, _} = Materials.set_enabled(off, false)

    assert response(get(log_in_user(conn, owner), ~p"/materials/#{off.uuid}"), 200)
    assert response(get(log_in_user(conn, user_fixture()), ~p"/materials/#{off.uuid}"), 404)
  end

  describe "the slides" do
    setup %{event: event} do
      hash = "mc#{System.unique_integer([:positive])}"
      presentation_file_fixture(%{event: event, hash: hash})
      dir = Path.join([Application.get_env(:claper, :storage_dir), "uploads", hash])
      File.mkdir_p!(dir)
      File.write!(Path.join(dir, "original.pdf"), @pdf)
      on_exit(fn -> File.rm_rf(dir) end)
      %{hash: hash}
    end

    test "only after the event, when switched on", %{conn: conn, event: event} do
      assert response(get(conn, ~p"/materials/slides/#{event.uuid}"), 404)

      {:ok, event} = Materials.set_take_home_slides(event, true)
      assert response(get(conn, ~p"/materials/slides/#{event.uuid}"), 404), "still running"

      {:ok, _} = event |> Ecto.Changeset.change(expired_at: minutes(-1)) |> Claper.Repo.update()
      conn = get(conn, ~p"/materials/slides/#{event.uuid}")
      assert response(conn, 200) == @pdf
      assert [disposition] = get_resp_header(conn, "content-disposition")
      assert disposition =~ "attachment"
    end

    test "the original upload is never a public file", %{conn: conn, hash: hash} do
      assert response(get(conn, "/uploads/#{hash}/original.pdf"), 404)
      assert response(get(conn, "/uploads/#{hash}/original.pptx"), 404)
    end
  end
end
