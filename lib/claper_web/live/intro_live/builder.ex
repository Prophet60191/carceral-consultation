defmodule ClaperWeb.IntroLive.Builder do
  @moduledoc """
  The intro page builder (docs/INTRO.md, step 2) at `/e/<code>/intro`, for
  the event's leaders. Blocks are added with the buttons at the top, listed
  in order (move up/down, edit, remove), and edited in a dialog driven by the
  URL (`?add=<kind>`, `?edit=<id>`). A phone-sized preview beside it uses the
  same component the phones do (`ClaperWeb.IntroLive.Components.page/1`).
  """
  use ClaperWeb, :live_view

  on_mount(ClaperWeb.UserLiveAuth)

  alias Claper.Intro
  alias Claper.Intro.Block
  alias ClaperWeb.IntroLive.Components

  @max_image_bytes 8_000_000

  @impl true
  def mount(params, session, socket) do
    with %{"locale" => locale} <- session do
      Gettext.put_locale(ClaperWeb.Gettext, locale)
    end

    case load_scope(socket, params) do
      {:ok, socket} ->
        {:ok,
         socket
         |> assign(page_title: gettext("Intro page"), editor: nil, title_error: nil)
         |> load_page()
         |> assign_library()
         |> allow_upload(:image,
           accept: Intro.image_extensions(),
           max_entries: 1,
           max_file_size: @max_image_bytes
         )
         |> allow_upload(:banner,
           accept: Intro.image_extensions(),
           max_entries: 1,
           max_file_size: @max_image_bytes
         )}

      :error ->
        {:ok,
         socket |> put_flash(:error, gettext("Intro page not found")) |> redirect(to: ~p"/events")}
    end
  end

  # An event's page (its leaders) or one of the user's library pages.
  defp load_scope(socket, %{"code" => code}) do
    user = socket.assigns.current_user
    event = Claper.Events.get_event_with_code(code, [:user])

    if event && leader?(user, event),
      do: {:ok, assign(socket, event: event, library_id: nil)},
      else: :error
  end

  defp load_scope(socket, %{"id" => id}) do
    case Intro.get_library_page(id, socket.assigns.current_user.id) do
      nil -> :error
      page -> {:ok, assign(socket, event: nil, library_id: page.id)}
    end
  end

  defp leader?(user, event),
    do: event.user_id == user.id || Claper.Events.led_by?(user.email, event)

  defp load_page(%{assigns: %{event: nil, library_id: id}} = socket),
    do: assign_page(socket, Intro.get_library_page(id, socket.assigns.current_user.id))

  defp load_page(socket), do: assign_page(socket, Intro.ensure_event_page(socket.assigns.event))

  # The page, and each interaction block's content (for its title in the list).
  defp assign_page(socket, page) do
    contents =
      for block <- page.blocks,
          Block.interaction?(block),
          into: %{},
          do: {block.id, Intro.load_content(block)}

    assign(socket, page: page, contents: contents)
  end

  # After a change: the page again here, in the phone preview, and on every
  # phone showing it.
  defp changed(socket) do
    previous_id = socket.assigns.page.id
    socket = load_page(socket)
    # Using a library page makes a new page for the event: its preview follows.
    Intro.broadcast_changed(socket.assigns.page, previous_id)
    socket
  end

  def preview_path(%{event: nil, library_id: id}), do: ~p"/intros/#{id}/preview"
  def preview_path(%{event: event}), do: ~p"/e/#{event.code}/intro/preview"

  # The user's library, offered in an event's builder (save to / replace from).
  defp assign_library(%{assigns: %{event: nil}} = socket), do: assign(socket, :library, [])

  defp assign_library(socket),
    do: assign(socket, :library, Intro.list_library(socket.assigns.current_user.id))

  @impl true
  def handle_params(params, _url, socket),
    do: {:noreply, assign(socket, :editor, editor_for(params, socket.assigns.page))}

  # Interactions open their own editor (the one used on slides) with an intro
  # target (ClaperWeb.BreakoutLive.PieceEditor); other blocks the form here.
  defp editor_for(%{"add" => kind}, page) do
    cond do
      kind in Block.interaction_kinds() ->
        %{
          action: :new,
          kind: kind,
          interaction: true,
          target: {:intro_new, page},
          content: ClaperWeb.BreakoutLive.PieceEditor.blank(kind)
        }

      kind in Block.kinds() and kind != "divider" ->
        %{action: :new, kind: kind, block: nil, params: blank(kind), errors: %{}}

      true ->
        nil
    end
  end

  defp editor_for(%{"edit" => id}, page) do
    case Intro.get_block_for_page(id, page) do
      %Block{kind: "divider"} ->
        nil

      %Block{kind: kind} = block when kind in ["poll", "quiz", "form", "word_cloud", "embed"] ->
        %{
          action: :edit,
          kind: kind,
          interaction: true,
          target: {:intro_edit, block},
          content: Intro.load_content(block)
        }

      %Block{kind: kind} = block ->
        %{action: :edit, kind: kind, block: block, params: block.data, errors: %{}}

      _ ->
        nil
    end
  end

  defp editor_for(_params, _page), do: nil

  defp blank("agenda"), do: %{"items" => [%{"time" => "", "title" => ""}]}
  defp blank(_kind), do: %{}

  def base_path(%{event: nil, library_id: id}), do: ~p"/intros/#{id}"
  def base_path(%{event: event}), do: ~p"/e/#{event.code}/intro"

  def crumbs(%{event: nil, page: page}),
    do: [{gettext("Intro library"), ~p"/intros"}, {page.title, nil}]

  def crumbs(%{event: event}),
    do: [{event.name, ~p"/e/#{event.code}/manage"}, {gettext("Intro page"), nil}]

  ## The library

  @impl true
  def handle_event("rename", %{"title" => title}, %{assigns: %{event: nil, page: page}} = socket) do
    case Intro.rename_library_page(page, title) do
      {:ok, _} -> {:noreply, socket |> assign(:title_error, nil) |> load_page()}
      {:error, _} -> {:noreply, assign(socket, :title_error, gettext("Give it a name"))}
    end
  end

  def handle_event("save_to_library", %{"title" => title}, %{assigns: %{event: event}} = socket)
      when not is_nil(event) do
    case Intro.save_to_library(socket.assigns.page, socket.assigns.current_user.id, title) do
      {:ok, _} ->
        {:noreply,
         socket
         |> assign_library()
         |> ClaperWeb.Toast.push(:success, gettext("Saved a copy to your intro library"))}

      {:error, _} ->
        {:noreply, ClaperWeb.Toast.push(socket, :error, gettext("Give the copy a name"))}
    end
  end

  def handle_event("use_library", %{"library_id" => id}, %{assigns: %{event: event}} = socket)
      when not is_nil(event) do
    case Intro.get_library_page(id, socket.assigns.current_user.id) do
      nil ->
        {:noreply, socket}

      library_page ->
        {:ok, _} = Intro.copy_page_to_event(library_page, event)

        {:noreply,
         socket
         |> changed()
         |> ClaperWeb.Toast.push(
           :success,
           gettext("The intro page now uses \"%{title}\"", title: library_page.title)
         )}
    end
  end

  ## Blocks

  def handle_event("add_divider", _params, socket) do
    {:ok, _} = Intro.add_block(socket.assigns.page, "divider", %{})
    {:noreply, changed(socket)}
  end

  def handle_event("move", %{"id" => id, "dir" => dir}, socket) when dir in ["up", "down"] do
    with %Block{} = block <- Intro.get_block_for_page(id, socket.assigns.page) do
      Intro.move_block(block, String.to_existing_atom(dir))
    end

    {:noreply, changed(socket)}
  end

  def handle_event("delete", %{"id" => id}, socket) do
    with %Block{} = block <- Intro.get_block_for_page(id, socket.assigns.page) do
      {:ok, _} = Intro.delete_block(block)
    end

    {:noreply, changed(socket)}
  end

  ## The block form

  def handle_event("change", params, %{assigns: %{editor: editor}} = socket)
      when not is_nil(editor) do
    {:noreply, assign(socket, :editor, %{editor | params: merge(editor, params["block"])})}
  end

  def handle_event(
        "agenda_add",
        _params,
        %{assigns: %{editor: %{kind: "agenda"} = editor}} = socket
      ) do
    items = rows(editor.params["items"]) ++ [%{"time" => "", "title" => ""}]
    {:noreply, assign(socket, :editor, put_in(editor, [:params, "items"], items))}
  end

  def handle_event(
        "agenda_remove",
        %{"index" => index},
        %{assigns: %{editor: %{kind: "agenda"} = editor}} = socket
      ) do
    items = editor.params["items"] |> rows() |> List.delete_at(String.to_integer(index))
    items = if items == [], do: [%{"time" => "", "title" => ""}], else: items
    {:noreply, assign(socket, :editor, put_in(editor, [:params, "items"], items))}
  end

  def handle_event("cancel_upload", %{"ref" => ref}, socket),
    do: {:noreply, cancel_upload(socket, :image, ref)}

  ## The brand at the top of the page (the shared switch row sends "checked")

  def handle_event("checked", %{"key" => "show_brand", "value" => value}, socket) do
    {:ok, _} = Intro.set_show_brand(socket.assigns.page, value == true)

    message =
      if value == true,
        do: gettext("The brand shows at the top"),
        else: gettext("The brand is hidden on this page")

    {:noreply, socket |> changed() |> ClaperWeb.Toast.push(:success, message)}
  end

  ## The banner across the top of the ticket card

  def handle_event("banner_change", _params, socket), do: {:noreply, socket}

  def handle_event("cancel_banner", %{"ref" => ref}, socket),
    do: {:noreply, cancel_upload(socket, :banner, ref)}

  def handle_event("save_banner", params, socket) do
    page = socket.assigns.page
    alt = params["banner_alt"] || ""

    src =
      case consume_uploaded_entries(socket, :banner, fn %{path: path}, entry ->
             {:ok, Intro.store_image(path, Path.extname(entry.client_name))}
           end) do
        [{:ok, src}] -> src
        _ -> page.banner_src
      end

    case src && Intro.set_banner(page, src, alt) do
      {:ok, _} ->
        {:noreply, socket |> changed() |> ClaperWeb.Toast.push(:success, gettext("Banner saved"))}

      _ ->
        {:noreply,
         ClaperWeb.Toast.push(socket, :error, gettext("Choose an image for the banner"))}
    end
  end

  def handle_event("remove_banner", _params, socket) do
    {:ok, _} = Intro.remove_banner(socket.assigns.page)
    {:noreply, socket |> changed() |> ClaperWeb.Toast.push(:success, gettext("Banner removed"))}
  end

  def handle_event("save", params, %{assigns: %{editor: editor}} = socket)
      when not is_nil(editor) do
    data = merge(editor, params["block"])

    data =
      case consume_image(socket) do
        {:ok, src} -> Map.put(data, "src", src)
        :none -> data
      end

    result =
      case editor.action do
        :new -> Intro.add_block(socket.assigns.page, editor.kind, data)
        :edit -> Intro.update_block(editor.block, data)
      end

    case result do
      {:ok, _block} ->
        {:noreply, socket |> changed() |> push_patch(to: base_path(socket.assigns))}

      {:error, changeset} ->
        {:noreply, assign(socket, :editor, %{editor | params: data, errors: errors(changeset)})}
    end
  end

  def handle_event(_event, _params, socket), do: {:noreply, socket}

  defp consume_image(socket) do
    case consume_uploaded_entries(socket, :image, fn %{path: path}, entry ->
           {:ok, Intro.store_image(path, Path.extname(entry.client_name))}
         end) do
      [{:ok, src}] -> {:ok, src}
      _ -> :none
    end
  end

  # Form values over what the editor holds; agenda rows come as a map by index.
  defp merge(editor, nil), do: editor.params

  defp merge(editor, values) when is_map(values) do
    values =
      if Map.has_key?(values, "items"),
        do: Map.put(values, "items", rows(values["items"])),
        else: values

    Map.merge(editor.params, values)
  end

  defp rows(items) when is_list(items), do: items

  defp rows(items) when is_map(items) do
    items
    |> Enum.sort_by(fn {k, _} -> String.to_integer(k) end)
    |> Enum.map(fn {_, v} -> v end)
  end

  defp rows(_), do: []

  defp errors(changeset) do
    Map.new(changeset.errors, fn {field, {message, _}} -> {to_string(field), message} end)
  end

  ## Helpers for the template

  attr :label, :string, required: true
  attr :error, :string, default: nil
  slot :inner_block, required: true

  def field(assigns) do
    ~H"""
    <label class="flex flex-col gap-1">
      <span class="text-sm font-bold text-base-content">{@label}</span>
      {render_slot(@inner_block)}
      <span :if={@error} class="text-sm text-error">{@error}</span>
    </label>
    """
  end

  def editor_title(%{action: :new, kind: kind}),
    do: gettext("Add: %{kind}", kind: Components.kind_label(kind))

  def editor_title(%{action: :edit, kind: kind}),
    do: gettext("Edit: %{kind}", kind: Components.kind_label(kind))

  def upload_error(:too_large), do: gettext("That image is larger than 8 MB.")
  def upload_error(:not_accepted), do: gettext("Use a PNG, JPG, WebP or GIF image.")
  def upload_error(:too_many_files), do: gettext("Choose one image.")
  def upload_error(_), do: gettext("That image couldn't be uploaded.")
end
