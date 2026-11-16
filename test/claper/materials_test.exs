defmodule Claper.MaterialsTest do
  use Claper.DataCase, async: false

  import Claper.EventsFixtures
  import Claper.PresentationsFixtures

  alias Claper.Materials
  alias Claper.Materials.Material

  @pdf "%PDF-1.4\n1 0 obj << >> endobj\ntrailer << >>\n%%EOF\n"

  defp tmp_file(contents) do
    path = Path.join(System.tmp_dir!(), "material-#{System.unique_integer([:positive])}.pdf")
    File.write!(path, contents)
    on_exit(fn -> File.rm(path) end)
    path
  end

  defp event_with_cleanup(attrs \\ %{}) do
    event = event_fixture(attrs)
    on_exit(fn -> Materials.delete_event_files(event) end)
    event
  end

  defp add(event, kind, title \\ "Worksheet", opts \\ []) do
    {:ok, materials} =
      Materials.create_material(
        event,
        %{kind: kind, title: title, original_name: "w.pdf"},
        tmp_file(@pdf),
        opts
      )

    materials
  end

  defp minutes(n),
    do: NaiveDateTime.add(NaiveDateTime.utc_now(), n * 60) |> NaiveDateTime.truncate(:second)

  describe "adding" do
    test "stores a PDF in its list, in order, switched on" do
      event = event_with_cleanup()
      [first] = add(event, "handout", "First")
      [second] = add(event, "handout", "Second")

      assert [%{title: "First", position: 0}, %{title: "Second", position: 1}] =
               Materials.list_materials(event, "handout")

      assert first.enabled
      assert File.read!(Materials.file_path(second, event)) == @pdf
      assert Materials.list_materials(event, "take_home") == []
    end

    test "a handout can also go to take-home, as a separate item" do
      event = event_with_cleanup()
      [handout, take_home] = add(event, "handout", "Worksheet", also_take_home: true)

      assert handout.kind == "handout" and take_home.kind == "take_home"
      assert handout.uuid != take_home.uuid
      assert File.regular?(Materials.file_path(take_home, event))

      {:ok, _} = Materials.set_enabled(handout, false)
      assert [%{enabled: true}] = Materials.list_materials(event, "take_home")
    end

    test "refuses what isn't a PDF, an empty file, and a missing title" do
      event = event_with_cleanup()
      attrs = %{kind: "handout", title: "Bad", original_name: "x.pdf"}

      assert {:error, :not_pdf} =
               Materials.create_material(event, attrs, tmp_file("<html>not a pdf</html>"))

      assert {:error, :empty} = Materials.create_material(event, attrs, tmp_file(""))

      assert {:error, %Ecto.Changeset{}} =
               Materials.create_material(event, %{attrs | title: "  "}, tmp_file(@pdf))

      assert Materials.list_materials(event, "handout") == []
    end

    test "refuses a file over 25 MB" do
      event = event_with_cleanup()
      big = tmp_file("%PDF-" <> :binary.copy("a", Materials.max_bytes()))

      assert {:error, :too_large} =
               Materials.create_material(event, %{kind: "take_home", title: "Big"}, big)
    end
  end

  describe "changing" do
    test "rename, move and delete (with its file)" do
      event = event_with_cleanup()
      [a] = add(event, "take_home", "A")
      [b] = add(event, "take_home", "B")

      {:ok, _} = Materials.rename(a, "Resource guide")
      {:ok, _} = Materials.move(b, :up)

      assert ["B", "Resource guide"] =
               event |> Materials.list_materials("take_home") |> Enum.map(& &1.title)

      path = Materials.file_path(b, event)
      {:ok, _} = Materials.delete_material(b)
      refute File.exists?(path)
      assert [%{title: "Resource guide"}] = Materials.list_materials(event, "take_home")
    end

    test "changes are announced to the event's screens" do
      event = event_with_cleanup()
      Materials.subscribe(event)
      [m] = add(event, "handout")
      assert_receive :materials_changed
      {:ok, _} = Materials.set_enabled(m, false)
      assert_receive :materials_changed
    end

    test "counts downloads" do
      event = event_with_cleanup()
      [m] = add(event, "take_home")
      Materials.record_download(m)
      Materials.record_download(m)
      assert Repo.get!(Material, m.id).downloads == 2
    end
  end

  describe "when things are available" do
    test "the take-home page: from the end until 7 days later, unless set" do
      event = event_with_cleanup(%{started_at: minutes(-120), expired_at: minutes(-60)})
      assert Materials.take_home_until(event) == NaiveDateTime.add(event.expired_at, 7 * 86_400)
      assert Materials.take_home_open?(event)

      {:ok, event} = Materials.set_take_home_until(event, minutes(-1))
      refute Materials.take_home_open?(event)
      assert Materials.take_home_closed?(event)

      assert {:error, :before_start} = Materials.set_take_home_until(event, minutes(-500))
    end

    test "nothing to take home before the end" do
      running = event_with_cleanup(%{expired_at: nil})
      refute Materials.take_home_open?(running)
      refute Materials.take_home_closed?(running)
      assert Materials.take_home_until(running) == nil

      scheduled = event_with_cleanup(%{expired_at: minutes(60)})
      refute Materials.take_home_open?(scheduled)
    end

    test "handouts while the event runs; take-home after; never when off" do
      event = event_with_cleanup(%{expired_at: nil})
      [handout] = add(event, "handout")
      [take_home] = add(event, "take_home")
      now = NaiveDateTime.utc_now()

      assert Materials.available?(handout, event, now)
      refute Materials.available?(take_home, event, now)

      ended = %{event | expired_at: minutes(-1)}
      refute Materials.available?(handout, ended, now)
      assert Materials.available?(take_home, ended, now)
      refute Materials.available?(%{take_home | enabled: false}, ended, now)
    end

    test "the slides: only when switched on, after the event, and if there is a PDF" do
      event = event_with_cleanup(%{started_at: minutes(-120), expired_at: minutes(-60)})
      hash = "mat#{System.unique_integer([:positive])}"
      presentation_file_fixture(%{event: event, hash: hash})
      dir = Path.join([Application.get_env(:claper, :storage_dir), "uploads", hash])
      on_exit(fn -> File.rm_rf(dir) end)
      now = NaiveDateTime.utc_now()

      refute Materials.slides_available?(event, now)
      {:ok, event} = Materials.set_take_home_slides(event, true)
      refute Materials.slides_available?(event, now), "no PDF yet"

      File.mkdir_p!(dir)
      File.write!(Path.join(dir, "original.pdf"), @pdf)
      assert Materials.slides_available?(event, now)
    end
  end

  describe "with the event" do
    test "duplicating copies materials, files and the slides switch, not the time" do
      user = Claper.AccountsFixtures.user_fixture()
      event = event_with_cleanup(%{user: user})
      presentation_file_fixture(%{event: event})
      [handout] = add(event, "handout", "Worksheet")
      {:ok, _} = Materials.set_enabled(handout, false)
      add(event, "take_home", "Guide")
      {:ok, event} = Materials.set_take_home_slides(event, true)
      {:ok, event} = Materials.set_take_home_until(event, minutes(600))

      {:ok, copy} = Claper.Events.duplicate_event(user.id, event.uuid)
      copy = Repo.get!(Claper.Events.Event, copy.id)
      on_exit(fn -> Materials.delete_event_files(copy) end)

      assert [%{title: "Worksheet", enabled: false} = h] =
               Materials.list_materials(copy, "handout")

      assert [%{title: "Guide"}] = Materials.list_materials(copy, "take_home")
      assert File.regular?(Materials.file_path(h, copy))
      assert copy.take_home_slides
      assert copy.take_home_until == nil
    end

    test "deleting the event deletes its materials and files" do
      event = event_with_cleanup()
      presentation_file_fixture(%{event: event})
      [m] = add(event, "handout")
      path = Materials.file_path(m, event)

      {:ok, _} = Claper.Events.delete_event(event)
      refute File.exists?(path)
      assert Repo.get(Material, m.id) == nil
    end
  end
end
