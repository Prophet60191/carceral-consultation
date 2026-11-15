defmodule Claper.Intro do
  @moduledoc """
  Intro pages (docs/INTRO.md): what participants see until the presenter
  starts the event. Every event has one (`ensure_event_page/1`, called when
  an event is created); it is built from blocks (`Claper.Intro.Block`).
  """
  import Ecto.Query
  use Gettext, backend: ClaperWeb.Gettext

  alias Claper.Repo
  alias Claper.Events.Event
  alias Claper.Intro.{Answer, Block, Page}
  alias Claper.Breakouts.PieceType

  @image_types ~w(png jpg jpeg webp gif)

  ## Pages

  @doc "An event's intro page with its blocks; created (starter page) if missing."
  def ensure_event_page(%Event{} = event) do
    case get_event_page(event) do
      nil ->
        {:ok, _page} = create_starter_page(event)
        get_event_page(event)

      page ->
        page
    end
  end

  @doc "An event's intro page with its blocks, or nil."
  def get_event_page(%Event{id: event_id}) do
    Page |> Repo.get_by(event_id: event_id) |> preload_blocks()
  end

  @doc """
  The starter page every new event gets (decision 1): a welcome heading,
  ready to be changed (the ticket above it already says when it starts).
  """
  def create_starter_page(%Event{} = event) do
    Repo.transaction(fn ->
      page =
        Repo.insert!(
          %Page{user_id: event.user_id, event_id: event.id},
          on_conflict: :nothing,
          conflict_target: {:unsafe_fragment, "(event_id) WHERE event_id IS NOT NULL"}
        )

      if page.id do
        insert_block!(page, 0, "heading", %{"text" => gettext("Welcome")})
      end

      page
    end)
  end

  @doc """
  Makes `page` (with its blocks) the intro page of `event`, replacing the one
  it has (duplicating an event copies the original's page).
  """
  def copy_page_to_event(%Page{} = page, %Event{} = event) do
    page = preload_blocks(page)

    Repo.transaction(fn ->
      from(p in Page, where: p.event_id == ^event.id) |> Repo.delete_all()

      copy =
        Repo.insert!(%Page{
          user_id: event.user_id,
          event_id: event.id,
          source_intro_page_id: page.id,
          banner_src: page.banner_src,
          banner_alt: page.banner_alt,
          show_brand: page.show_brand
        })

      Enum.each(page.blocks, &copy_block!(copy, &1))
      copy
    end)
  end

  ## The library (docs/INTRO.md, decision 4)

  @doc "A user's saved intro pages, by name, with their blocks."
  def list_library(user_id) do
    from(p in Page,
      where: p.user_id == ^user_id and is_nil(p.event_id),
      order_by: [asc: fragment("lower(?)", p.title), asc: p.id],
      preload: :blocks
    )
    |> Repo.all()
  end

  @doc "One of the user's library pages with its blocks, or nil."
  def get_library_page(id, user_id) do
    with {id, ""} <- Integer.parse(to_string(id)),
         %Page{} = page <-
           Repo.one(
             from p in Page, where: p.id == ^id and p.user_id == ^user_id and is_nil(p.event_id)
           ) do
      preload_blocks(page)
    else
      _ -> nil
    end
  end

  @doc "A new library page, starting from the same starter block as an event."
  def create_library_page(user_id, title) do
    Repo.transaction(fn ->
      case Repo.insert(Page.changeset(%Page{user_id: user_id}, %{title: title})) do
        {:ok, page} ->
          insert_block!(page, 0, "heading", %{"text" => gettext("Welcome")})
          page

        {:error, changeset} ->
          Repo.rollback(changeset)
      end
    end)
  end

  @doc "Saves a copy of a page (with its blocks) to the user's library."
  def save_to_library(%Page{} = page, user_id, title) do
    page = preload_blocks(page)

    Repo.transaction(fn ->
      case Repo.insert(
             Page.changeset(
               %Page{
                 user_id: user_id,
                 source_intro_page_id: page.id,
                 banner_src: page.banner_src,
                 banner_alt: page.banner_alt,
                 show_brand: page.show_brand
               },
               %{title: title}
             )
           ) do
        {:ok, copy} ->
          Enum.each(page.blocks, &copy_block!(copy, &1))
          copy

        {:error, changeset} ->
          Repo.rollback(changeset)
      end
    end)
  end

  @doc "Sets the page's banner (`src` an uploaded image) and its description."
  def set_banner(%Page{} = page, src, alt) do
    page |> Page.banner_changeset(%{banner_src: src, banner_alt: alt}) |> Repo.update()
  end

  @doc "Shows or hides the brand at the top of the page."
  def set_show_brand(%Page{} = page, show?) when is_boolean(show?),
    do: page |> Ecto.Changeset.change(show_brand: show?) |> Repo.update()

  def remove_banner(%Page{} = page),
    do: page |> Ecto.Changeset.change(banner_src: nil, banner_alt: nil) |> Repo.update()

  def rename_library_page(%Page{event_id: nil} = page, title),
    do: page |> Page.changeset(%{title: title}) |> Repo.update()

  def delete_library_page(%Page{event_id: nil} = page), do: Repo.delete(page)

  defp preload_blocks(nil), do: nil
  defp preload_blocks(page), do: Repo.preload(page, :blocks, force: true)

  ## Blocks

  @doc "Adds a block at the end of the page."
  def add_block(%Page{id: page_id} = page, kind, data) do
    position =
      Repo.one(from b in Block, where: b.intro_page_id == ^page_id, select: count(b.id))

    %Block{intro_page_id: page.id}
    |> Block.changeset(%{kind: kind, position: position, data: data})
    |> Repo.insert()
  end

  def update_block(%Block{} = block, data),
    do: block |> Block.changeset(%{kind: block.kind, data: data}) |> Repo.update()

  def delete_block(%Block{} = block) do
    with {:ok, block} <- Repo.delete(block) do
      renumber(block.intro_page_id)
      {:ok, block}
    end
  end

  @doc "A block of this page, or nil (never another page's)."
  def get_block_for_page(id, %Page{id: page_id}) do
    case Integer.parse(to_string(id)) do
      {id, ""} -> Repo.one(from b in Block, where: b.id == ^id and b.intro_page_id == ^page_id)
      _ -> nil
    end
  end

  @doc "Moves a block one place up or down; positions are rewritten 0, 1, 2…"
  def move_block(%Block{} = block, direction) when direction in [:up, :down] do
    blocks = ordered(block.intro_page_id)
    index = Enum.find_index(blocks, &(&1.id == block.id))
    target = if direction == :up, do: index - 1, else: index + 1

    if index && target >= 0 && target < length(blocks) do
      blocks
      |> List.replace_at(index, Enum.at(blocks, target))
      |> List.replace_at(target, Enum.at(blocks, index))
      |> write_positions()
    else
      {:ok, :unchanged}
    end
  end

  def change_block(%Block{} = block, attrs \\ %{}), do: Block.changeset(block, attrs)

  defp ordered(page_id),
    do:
      Repo.all(
        from b in Block,
          where: b.intro_page_id == ^page_id,
          order_by: [asc: b.position, asc: b.id]
      )

  defp renumber(page_id), do: page_id |> ordered() |> write_positions()

  defp write_positions(blocks) do
    Repo.transaction(fn ->
      blocks
      |> Enum.with_index()
      |> Enum.each(fn {b, i} ->
        from(x in Block, where: x.id == ^b.id) |> Repo.update_all(set: [position: i])
      end)
    end)
  end

  # A block onto another page; an interaction's content is copied with it
  # (never its answers).
  defp copy_block!(page, %Block{} = block) do
    copy = insert_block!(page, block.position, block.kind, block.data)

    if Block.interaction?(block) do
      module = PieceType.module_for!(block)

      case module.load(block) do
        nil -> :ok
        content -> {:ok, _} = module.copy_content(content, copy)
      end
    end

    copy
  end

  defp insert_block!(page, position, kind, data) do
    %Block{intro_page_id: page.id}
    |> Block.changeset(%{kind: kind, position: position, data: data})
    |> Repo.insert!()
  end

  @doc """
  Tells everyone showing a page that it changed: the builder's phone preview
  (`"intro_page:<id>"`) and, for an event's page, the phones in the event.
  `previous_id` is the page a preview was following, when it was replaced.
  """
  def broadcast_changed(%Page{} = page, previous_id \\ nil) do
    for id <- Enum.uniq(Enum.reject([page.id, previous_id], &is_nil/1)) do
      Phoenix.PubSub.broadcast(Claper.PubSub, "intro_page:#{id}", {:intro_page_updated, page.id})
    end

    if page.event_id do
      uuid = Repo.one(from e in Event, where: e.id == ^page.event_id, select: e.uuid)
      Phoenix.PubSub.broadcast(Claper.PubSub, "event:#{uuid}", :intro_updated)
    end

    :ok
  end

  ## Interactions (docs/INTRO.md, decisions 11-16)

  @doc """
  Adds an interaction block at the end of the page: the block and the
  interaction's content (`content_attrs`, as its editor sends them) in one
  transaction. `data` is the block's own settings (a form's `show_answers`).
  """
  def add_interaction(%Page{id: page_id} = page, kind, content_attrs, data \\ %{}) do
    position =
      Repo.one(from b in Block, where: b.intro_page_id == ^page_id, select: count(b.id))

    Repo.transaction(fn ->
      with {:ok, block} <-
             %Block{intro_page_id: page.id}
             |> Block.changeset(%{kind: kind, position: position, data: data})
             |> Repo.insert(),
           true <- Block.interaction?(block) || {:error, :not_an_interaction},
           {:ok, _content} <- PieceType.module_for!(block).create_content(block, content_attrs) do
        block
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  @doc "Changes an interaction block's content and its own settings together."
  def update_interaction(%Block{} = block, content_attrs, data \\ nil) do
    module = PieceType.module_for!(block)

    Repo.transaction(fn ->
      with {:ok, block} <- if(data, do: update_block(block, data), else: {:ok, block}),
           content when not is_nil(content) <- module.load(block) || {:error, :no_content},
           {:ok, content} <- module.update_content(content, content_attrs) do
        {block, content}
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  @doc "An interaction block's content (poll, quiz, form, word cloud, web content)."
  def load_content(%Block{} = block) do
    if Block.interaction?(block), do: PieceType.module_for!(block).load(block)
  end

  @doc """
  Saves a participant's answer (decision 12), replacing their earlier one.
  Refused once the event has started; an empty answer withdraws it.
  """
  def put_answer(%Claper.Events.Event{} = event, %Block{} = block, identifier, params) do
    with :ok <- answering_open(event),
         true <- Block.interaction?(block) || {:error, :not_an_interaction},
         module = PieceType.module_for!(block),
         true <- module.answerable?() || {:error, :not_answerable},
         content when not is_nil(content) <- module.load(block) || {:error, :no_content},
         {:ok, response} <- module.validate_response(content, params) do
      %Answer{intro_block_id: block.id, attendee_identifier: identifier, response: response}
      |> Repo.insert(
        on_conflict: [set: [response: response, updated_at: NaiveDateTime.utc_now(:second)]],
        conflict_target: [:intro_block_id, :attendee_identifier],
        returning: true
      )
    end
  end

  @doc "Takes back a participant's answer (they cleared it) while answering is open."
  def withdraw_answer(%Claper.Events.Event{} = event, %Block{} = block, identifier) do
    with :ok <- answering_open(event) do
      from(a in Answer,
        where: a.intro_block_id == ^block.id and a.attendee_identifier == ^identifier
      )
      |> Repo.delete_all()

      :ok
    end
  end

  # Answers are taken until the presenter starts the event (Back to intro reopens).
  defp answering_open(event) do
    state =
      Repo.get_by(Claper.Presentations.PresentationState,
        presentation_file_id: presentation_file_id(event)
      )

    if state && state.started, do: {:error, :started}, else: :ok
  end

  defp presentation_file_id(%Claper.Events.Event{id: id}) do
    Repo.one(
      from pf in Claper.Presentations.PresentationFile, where: pf.event_id == ^id, select: pf.id
    )
  end

  @doc "A participant's answers on a page, by block id."
  def answers_for(%Page{id: page_id}, identifier) do
    from(a in Answer,
      join: b in Block,
      on: b.id == a.intro_block_id,
      where: b.intro_page_id == ^page_id and a.attendee_identifier == ^identifier,
      select: {a.intro_block_id, a.response}
    )
    |> Repo.all()
    |> Map.new()
  end

  @doc """
  The live results of a page's interactions, in order, for the big screen
  (decisions 13-15): each answerable block with its content, the number of
  answers and the interaction's summary. Web content has none and is left out.
  """
  def results(%Page{} = page) do
    blocks = Enum.filter(page.blocks, &Block.interaction?/1)
    ids = Enum.map(blocks, & &1.id)

    responses =
      from(a in Answer,
        where: a.intro_block_id in ^ids,
        order_by: [asc: a.inserted_at, asc: a.id]
      )
      |> Repo.all()
      |> Enum.group_by(& &1.intro_block_id, & &1.response)

    for block <- blocks,
        module = PieceType.module_for!(block),
        module.answerable?(),
        content = module.load(block),
        content != nil do
      answers = Map.get(responses, block.id, [])

      %{
        block: block,
        content: content,
        count: length(answers),
        summary: module.summarize(content, answers)
      }
    end
  end

  ## Images

  @doc "Image file types an image block accepts."
  def image_extensions, do: Enum.map(@image_types, &".#{&1}")

  @doc """
  Stores an uploaded image with the app's other uploads and returns its
  address (`/uploads/intro/<uuid>.<ext>`).
  """
  def store_image(tmp_path, extension) do
    ext = extension |> String.trim_leading(".") |> String.downcase()

    if ext in @image_types do
      name = "#{Ecto.UUID.generate()}.#{ext}"
      dir = Path.join([Application.get_env(:claper, :storage_dir), "uploads", "intro"])
      File.mkdir_p!(dir)
      File.cp!(tmp_path, Path.join(dir, name))
      {:ok, "/uploads/intro/#{name}"}
    else
      {:error, :type}
    end
  end
end
