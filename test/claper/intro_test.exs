defmodule Claper.IntroTest do
  @moduledoc "Intro pages (docs/INTRO.md, step 2)."
  use Claper.DataCase

  import Claper.{AccountsFixtures, EventsFixtures}

  alias Claper.Intro
  alias Claper.Intro.Block

  setup do
    user = user_fixture()
    event = event_fixture(%{user: user})
    %{user: user, event: event, page: Intro.get_event_page(event)}
  end

  test "every new event has a starter page", %{page: page} do
    assert [%Block{kind: "heading", data: %{"text" => "Welcome"}}] = page.blocks
  end

  test "each kind keeps only its own, cleaned fields", %{page: page} do
    assert {:ok, b} = Intro.add_block(page, "heading", %{"text" => "  Hello  ", "extra" => "x"})
    assert b.data == %{"text" => "Hello"}

    assert {:ok, b} = Intro.add_block(page, "stat", %{"value" => "26 years", "label" => "served"})
    assert b.data == %{"value" => "26 years", "label" => "served"}

    assert {:ok, b} =
             Intro.add_block(page, "agenda", %{
               "items" => %{
                 "1" => %{"time" => "", "title" => "Q&A"},
                 "0" => %{"time" => "6:00 PM", "title" => "Welcome"},
                 "2" => %{"time" => "", "title" => ""}
               }
             })

    assert b.data["items"] == [
             %{"time" => "6:00 PM", "title" => "Welcome"},
             %{"time" => "", "title" => "Q&A"}
           ]

    assert {:ok, b} =
             Intro.add_block(page, "link", %{
               "label" => "Report",
               "url" => "https://example.org/r"
             })

    assert b.data["url"] == "https://example.org/r"
    assert {:ok, %{data: %{}}} = Intro.add_block(page, "divider", %{"anything" => 1})
  end

  test "blocks that aren't complete or safe are refused", %{page: page} do
    assert {:error, cs} = Intro.add_block(page, "heading", %{"text" => "   "})
    assert %{text: _} = errors_on(cs)

    assert {:error, cs} =
             Intro.add_block(page, "link", %{"label" => "Go", "url" => "javascript:alert(1)"})

    assert %{url: _} = errors_on(cs)

    assert {:error, cs} = Intro.add_block(page, "image", %{"src" => "https://elsewhere/x.png"})
    assert %{src: _} = errors_on(cs)

    assert {:error, cs} =
             Intro.add_block(page, "agenda", %{"items" => %{"0" => %{"time" => "6"}}})

    assert %{items: _} = errors_on(cs)

    assert {:error, cs} = Intro.add_block(page, "video", %{})
    assert %{kind: _} = errors_on(cs)
  end

  test "blocks move and are removed, positions kept tidy", %{event: event, page: page} do
    [heading] = page.blocks
    {:ok, text} = Intro.add_block(page, "text", %{"body" => "Read this first."})
    {:ok, _} = Intro.move_block(text, :up)
    assert [%{kind: "text"}, %{kind: "heading"}] = Intro.get_event_page(event).blocks

    {:ok, _} = Intro.delete_block(text)
    assert [%{id: id, position: 0}] = Intro.get_event_page(event).blocks
    assert id == heading.id
  end

  test "a block of another page is out of reach", %{page: page} do
    other = Intro.get_event_page(event_fixture())
    [block | _] = other.blocks
    assert Intro.get_block_for_page(block.id, page) == nil
    assert Intro.get_block_for_page("1; DROP", page) == nil
  end

  test "duplicating an event copies its intro page", %{user: user, event: event, page: page} do
    {:ok, _} = Intro.add_block(page, "stat", %{"value" => "12", "label" => "hearings"})
    {:ok, copy} = Claper.Events.duplicate_event(user.id, event.uuid)

    assert Enum.map(Intro.get_event_page(copy).blocks, & &1.kind) == ["heading", "stat"]
    assert length(Repo.all(from p in Claper.Intro.Page, where: p.event_id == ^copy.id)) == 1
  end

  test "an uploaded image is stored with the app's uploads" do
    path = Path.join(System.tmp_dir!(), "intro-test.png")
    File.write!(path, "png")
    assert {:ok, "/uploads/intro/" <> name} = Intro.store_image(path, ".PNG")
    assert name =~ ~r/\.png\z/
    assert {:error, :type} = Intro.store_image(path, ".exe")
  end

  describe "the library" do
    test "a page is saved, listed, used in another event, renamed and deleted", %{
      user: user,
      event: event,
      page: page
    } do
      {:ok, _} = Intro.add_block(page, "stat", %{"value" => "12", "label" => "hearings"})
      assert {:error, _} = Intro.save_to_library(page, user.id, "  ")
      {:ok, saved} = Intro.save_to_library(page, user.id, "Standard welcome")

      assert [%{title: "Standard welcome", event_id: nil, blocks: blocks}] =
               Intro.list_library(user.id)

      assert Enum.map(blocks, & &1.kind) == ["heading", "stat"]

      # Used in another event: its page becomes a copy, the library page stays.
      other = event_fixture(%{user: user})
      {:ok, _} = Intro.copy_page_to_event(Intro.get_library_page(saved.id, user.id), other)

      assert Enum.map(Intro.get_event_page(other).blocks, & &1.kind) == ["heading", "stat"]

      # Changing the library page later doesn't change the event's copy.
      lib = Intro.get_library_page(saved.id, user.id)
      {:ok, _} = Intro.delete_block(List.last(lib.blocks))
      assert length(Intro.get_event_page(other).blocks) == 2

      {:ok, renamed} = Intro.rename_library_page(lib, "Welcome v2")
      assert renamed.title == "Welcome v2"

      {:ok, _} = Intro.delete_library_page(renamed)
      assert Intro.list_library(user.id) == []
      assert length(Intro.get_event_page(event).blocks) == 2
    end

    test "other people's library pages and event pages are out of reach", %{
      user: user,
      page: page
    } do
      {:ok, mine} = Intro.create_library_page(user.id, "Mine")
      stranger = user_fixture()
      assert Intro.get_library_page(mine.id, stranger.id) == nil
      # An event's page is never a library page.
      assert Intro.get_library_page(page.id, user.id) == nil
      assert {:error, _} = Intro.create_library_page(user.id, "")
    end
  end

  test "a banner is an uploaded image, copied with the page, and can be removed", %{
    user: user,
    event: event,
    page: page
  } do
    assert {:error, _} = Intro.set_banner(page, "https://elsewhere/x.png", "")
    {:ok, page} = Intro.set_banner(page, "/uploads/intro/0a1b-2c.jpg", "  The hearing room ")

    assert {page.banner_src, page.banner_alt} ==
             {"/uploads/intro/0a1b-2c.jpg", "The hearing room"}

    {:ok, copy} = Claper.Events.duplicate_event(user.id, event.uuid)
    assert Intro.get_event_page(copy).banner_src == "/uploads/intro/0a1b-2c.jpg"

    {:ok, saved} = Intro.save_to_library(page, user.id, "With banner")
    assert saved.banner_alt == "The hearing room"

    {:ok, page} = Intro.remove_banner(page)
    assert page.banner_src == nil
  end

  describe "interactions (decisions 11-16)" do
    setup %{event: event} do
      pf = Claper.PresentationsFixtures.presentation_file_fixture(%{event: event})

      state =
        Claper.PresentationsFixtures.presentation_state_fixture(%{
          presentation_file: pf,
          started: false
        })

      %{state: state}
    end

    defp poll_on(page) do
      {:ok, block} =
        Intro.add_interaction(page, "poll", %{
          title: "Have you been to a parole hearing?",
          poll_opts: [%{content: "Yes"}, %{content: "No"}]
        })

      {block, Intro.load_content(block)}
    end

    test "a poll is a block whose content lives in the polls table", %{page: page} do
      {block, poll} = poll_on(page)
      assert block.kind == "poll"
      assert poll.intro_block_id == block.id
      assert poll.presentation_file_id == nil
      assert Enum.map(poll.poll_opts, & &1.content) == ["Yes", "No"]

      assert {:error, _} = Intro.add_interaction(page, "poll", %{title: ""})
      assert length(Intro.get_event_page(page_event(page)).blocks) == 2
    end

    test "answers are taken, changed and withdrawn until the event starts", %{
      event: event,
      page: page,
      state: state
    } do
      {block, poll} = poll_on(page)
      [yes, no] = Enum.map(poll.poll_opts, & &1.id)

      {:ok, _} = Intro.put_answer(event, block, "phone-a", %{"options" => [yes]})
      {:ok, _} = Intro.put_answer(event, block, "phone-b", %{"options" => [no]})
      {:ok, _} = Intro.put_answer(event, block, "phone-b", %{"options" => [yes]})
      assert {:error, _} = Intro.put_answer(event, block, "phone-c", %{"options" => [999_999]})

      assert Intro.answers_for(page, "phone-b") == %{block.id => %{"options" => [yes]}}

      [%{count: 2, summary: %{options: [%{count: 2}, %{count: 0}]}}] =
        Intro.results(Intro.get_event_page(event))

      :ok = Intro.withdraw_answer(event, block, "phone-b")
      assert [%{count: 1}] = Intro.results(Intro.get_event_page(event))

      {:ok, _} = Claper.Presentations.update_presentation_state(state, %{started: true})
      assert {:error, :started} = Intro.put_answer(event, block, "phone-d", %{"options" => [no]})
      assert {:error, :started} = Intro.withdraw_answer(event, block, "phone-a")

      # Back to intro opens answering again.
      {:ok, _} =
        Claper.Presentations.update_presentation_state(
          Repo.get!(Claper.Presentations.PresentationState, state.id),
          %{started: false}
        )

      assert {:ok, _} = Intro.put_answer(event, block, "phone-d", %{"options" => [no]})
    end

    test "web content has no results; copies take the content, never answers", %{
      user: user,
      event: event,
      page: page
    } do
      {block, poll} = poll_on(page)

      {:ok, _} =
        Intro.add_interaction(page, "embed", %{
          title: "Report",
          provider: "custom",
          content: "<iframe src=\"https://www.youtube.com/embed/9bZkp7q19f0\"></iframe>"
        })

      {:ok, _} =
        Intro.put_answer(event, block, "phone-a", %{"options" => [hd(poll.poll_opts).id]})

      assert [%{block: %{kind: "poll"}}] = Intro.results(Intro.get_event_page(event))

      {:ok, saved} = Intro.save_to_library(Intro.get_event_page(event), user.id, "With a poll")
      lib = Intro.get_library_page(saved.id, user.id)
      lib_poll = lib.blocks |> Enum.find(&(&1.kind == "poll")) |> Intro.load_content()
      assert lib_poll.id != poll.id
      assert Enum.map(lib_poll.poll_opts, & &1.content) == ["Yes", "No"]
      assert [%{count: 0}] = Intro.results(lib)
    end

    test "a form keeps whether its answers show on the big screen", %{page: page} do
      {:ok, block} =
        Intro.add_interaction(
          page,
          "form",
          %{title: "Your hopes", fields: [%{name: "Hope", type: "text"}]},
          %{"show_answers" => "true"}
        )

      assert block.data == %{"show_answers" => true}

      {:ok, {block, _}} =
        Intro.update_interaction(block, %{title: "Hopes"}, %{"show_answers" => "false"})

      assert block.data == %{"show_answers" => false}
      assert Intro.load_content(block).title == "Hopes"
    end

    test "removing an interaction block removes its content and answers", %{
      event: event,
      page: page
    } do
      {block, poll} = poll_on(page)

      {:ok, _} =
        Intro.put_answer(event, block, "phone-a", %{"options" => [hd(poll.poll_opts).id]})

      {:ok, _} = Intro.delete_block(block)
      assert Repo.get(Claper.Polls.Poll, poll.id) == nil
      assert Repo.all(Claper.Intro.Answer) == []
    end
  end

  defp page_event(page), do: Repo.get!(Claper.Events.Event, page.event_id)
end
