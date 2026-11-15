defmodule ClaperWeb.BreakoutLive.Builder do
  @moduledoc """
  The breakout builder (docs/BREAKOUT.md, decision 15): its own page rather
  than a pop-up, for a breakout in an event or in the library.

    * `:event_new` / `:library_new` — name a new breakout (or, in an event,
      start from one in the library)
    * `:event_edit` / `:library_edit` — settings, cases and their pieces

  Settings save as you change them. Pieces are edited in a pop-up: typed
  text here, every other kind with that interaction's own editor in piece
  mode (`ClaperWeb.BreakoutLive.PieceEditor`). The pop-up is driven by the
  URL (`?add=<kind>&packet=<id>` or `?edit=<piece id>`), so the editors can
  return to this page when they save.
  """
  use ClaperWeb, :live_view

  on_mount(ClaperWeb.UserLiveAuth)

  alias Claper.Breakouts
  alias Claper.Breakouts.{Breakout, PieceType}

  @impl true
  def mount(params, session, socket) do
    with %{"locale" => locale} <- session do
      Gettext.put_locale(ClaperWeb.Gettext, locale)
    end

    case load_scope(socket, params) do
      {:ok, socket} ->
        {:ok, assign(socket, editor: nil, text_error: nil)}

      :error ->
        {:ok,
         socket |> put_flash(:error, gettext("Breakout not found")) |> redirect(to: ~p"/events")}
    end
  end

  # Where this breakout lives: an event the user leads, or their library.
  defp load_scope(socket, %{"code" => code} = params) do
    user = socket.assigns.current_user

    event =
      Claper.Events.get_event_with_code(code, [:user, presentation_file: :presentation_state])

    cond do
      is_nil(event) or not leader?(user, event) ->
        :error

      socket.assigns.live_action == :event_new ->
        {:ok, socket |> assign(event: event, breakout: nil) |> assign_new_form()}

      breakout = Breakouts.get_breakout_for_presentation(params["id"], event.presentation_file.id) ->
        {:ok, socket |> assign(event: event) |> assign_breakout(breakout)}

      true ->
        :error
    end
  end

  defp load_scope(socket, params) do
    user = socket.assigns.current_user

    cond do
      socket.assigns.live_action == :library_new ->
        {:ok, socket |> assign(event: nil, breakout: nil) |> assign_new_form()}

      breakout = Breakouts.get_library_breakout(params["id"], user.id) ->
        {:ok, socket |> assign(event: nil) |> assign_breakout(breakout)}

      true ->
        :error
    end
  end

  defp leader?(user, event),
    do: Claper.Events.led_by?(user.email, event) || event.user.id == user.id

  defp assign_new_form(socket) do
    library =
      if socket.assigns.event,
        do: Breakouts.list_library(socket.assigns.current_user.id),
        else: []

    socket
    |> assign(:page_title, gettext("New breakout"))
    |> assign(:library, library)
    |> assign(:form, to_form(Breakouts.change_breakout(%Breakout{})))
  end

  defp assign_breakout(socket, breakout) do
    breakout = Breakouts.get_breakout!(breakout.id)

    contents =
      for packet <- breakout.packets, piece <- packet.pieces, into: %{} do
        {piece.id, Breakouts.load_content(piece)}
      end

    socket
    |> assign(:page_title, breakout.title)
    |> assign(:breakout, breakout)
    |> assign(:contents, contents)
    |> assign(:form, to_form(Breakouts.change_breakout(breakout)))
  end

  defp reload(socket), do: assign_breakout(socket, socket.assigns.breakout)

  ## The pop-up editor, driven by the URL

  @impl true
  def handle_params(params, _url, %{assigns: %{breakout: %Breakout{} = breakout}} = socket) do
    {:noreply,
     assign(socket,
       editor: editor_for(params, breakout, socket.assigns.contents),
       text_error: nil
     )}
  end

  def handle_params(_params, _url, socket), do: {:noreply, socket}

  defp editor_for(%{"add" => kind, "packet" => packet_id}, breakout, _contents) do
    with module when not is_nil(module) <- PieceType.module_for(kind),
         packet when not is_nil(packet) <- find_packet(breakout, packet_id) do
      %{action: :new, kind: kind, packet: packet, piece: nil, content: blank(kind)}
    end
  end

  defp editor_for(%{"edit" => piece_id}, breakout, contents) do
    case find_piece(breakout, piece_id) do
      nil ->
        nil

      piece ->
        %{action: :edit, kind: piece.kind, packet: nil, piece: piece, content: contents[piece.id]}
    end
  end

  defp editor_for(_params, _breakout, _contents), do: nil

  defp find_packet(breakout, id), do: Enum.find(breakout.packets, &(to_string(&1.id) == id))

  defp find_piece(breakout, id) do
    breakout.packets |> Enum.flat_map(& &1.pieces) |> Enum.find(&(to_string(&1.id) == id))
  end

  # The blank content each editor starts from (the same as on a slide).
  defp blank("text"), do: nil
  defp blank(kind), do: ClaperWeb.BreakoutLive.PieceEditor.blank(kind)

  ## Paths

  def base_path(%{event: %{code: code}, breakout: %{id: id}}), do: ~p"/e/#{code}/breakouts/#{id}"
  def base_path(%{event: nil, breakout: %{id: id}}), do: ~p"/breakouts/#{id}"

  defp back_path(%{event: %{code: code}}), do: ~p"/e/#{code}/manage"
  defp back_path(%{event: nil}), do: ~p"/breakouts"

  def crumbs(%{event: event} = assigns) when not is_nil(event) do
    [
      {event.name, ~p"/e/#{event.code}/manage"},
      {page_crumb(assigns), nil}
    ]
  end

  def crumbs(assigns),
    do: [{gettext("Breakout library"), ~p"/breakouts"}, {page_crumb(assigns), nil}]

  defp page_crumb(%{breakout: nil}), do: gettext("New breakout")
  defp page_crumb(%{breakout: breakout}), do: breakout.title

  ## Creating

  @impl true
  def handle_event("create", %{"breakout" => params}, socket) do
    user = socket.assigns.current_user

    placement =
      case socket.assigns.event do
        nil ->
          %{user_id: user.id}

        event ->
          %{
            user_id: user.id,
            presentation_file_id: event.presentation_file.id,
            position: current_position(event)
          }
      end

    case Breakouts.create_breakout(params, placement) do
      {:ok, breakout} ->
        {:noreply, push_navigate(socket, to: base_path(%{socket.assigns | breakout: breakout}))}

      {:error, changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset))}
    end
  end

  def handle_event("use_library", %{"id" => id}, %{assigns: %{event: event}} = socket)
      when not is_nil(event) do
    user = socket.assigns.current_user

    with %Breakout{} = source <- Breakouts.get_library_breakout(id, user.id),
         {:ok, copy} <-
           Breakouts.copy_to_event(
             source,
             event.presentation_file.id,
             current_position(event),
             user.id
           ) do
      {:noreply, push_navigate(socket, to: base_path(%{socket.assigns | breakout: copy}))}
    else
      _ -> {:noreply, put_flash(socket, :error, gettext("Could not use that breakout"))}
    end
  end

  ## Settings (saved as they change)

  def handle_event("save_settings", %{"breakout" => params}, socket) do
    case Breakouts.update_breakout(socket.assigns.breakout, params) do
      {:ok, _} ->
        {:noreply, reload(socket)}

      {:error, changeset} ->
        {:noreply, assign(socket, :form, to_form(Map.put(changeset, :action, :validate)))}
    end
  end

  ## Material for each group (packets)

  def handle_event("add_packet", _params, socket) do
    case Breakouts.add_packet(socket.assigns.breakout, %{}) do
      {:ok, _} -> {:noreply, reload(socket)}
      _ -> {:noreply, socket}
    end
  end

  def handle_event("delete_packet", %{"id" => id}, socket) do
    with packet when not is_nil(packet) <- find_packet(socket.assigns.breakout, id),
         {:ok, _} <- Breakouts.delete_packet(packet) do
      {:noreply, reload(socket)}
    else
      _ -> {:noreply, socket}
    end
  end

  ## Pieces

  def handle_event("toggle_visible", %{"key" => id}, socket) do
    case find_piece(socket.assigns.breakout, id) do
      nil -> {:noreply, socket}
      piece -> update_piece(socket, id, %{visible_to_group: !piece.visible_to_group})
    end
  end

  def handle_event("move_piece", %{"id" => id, "dir" => dir}, socket)
      when dir in ["up", "down"] do
    case find_piece(socket.assigns.breakout, id) do
      nil ->
        {:noreply, socket}

      piece ->
        {:ok, _} = Breakouts.move_piece(piece, String.to_existing_atom(dir))
        {:noreply, reload(socket)}
    end
  end

  def handle_event("delete_piece", %{"id" => id}, socket) do
    case find_piece(socket.assigns.breakout, id) do
      nil ->
        {:noreply, socket}

      piece ->
        {:ok, _} = Breakouts.delete_piece(piece)
        {:noreply, reload(socket)}
    end
  end

  # Typed text has its own small editor here.
  def handle_event("save_text", %{"body" => body}, %{assigns: %{editor: editor}} = socket)
      when not is_nil(editor) do
    result =
      case editor.action do
        :new -> Breakouts.add_piece(editor.packet, %{kind: "text", body: body})
        :edit -> Breakouts.update_content(editor.piece, %{"body" => body})
      end

    case result do
      {:ok, _} ->
        {:noreply, socket |> reload() |> push_patch(to: base_path(socket.assigns))}

      {:error, _} ->
        {:noreply, assign(socket, :text_error, gettext("Write some text first"))}
    end
  end

  ## Library and removal

  def handle_event("save_to_library", _params, socket) do
    case Breakouts.save_to_library(socket.assigns.breakout, socket.assigns.current_user.id) do
      {:ok, _} ->
        {:noreply, put_flash(socket, :info, gettext("Saved a copy to your breakout library"))}

      _ ->
        {:noreply, put_flash(socket, :error, gettext("Could not save to the library"))}
    end
  end

  def handle_event("delete_breakout", _params, socket) do
    {:ok, _} = Breakouts.delete_breakout(socket.assigns.breakout)
    {:noreply, push_navigate(socket, to: back_path(socket.assigns))}
  end

  defp update_piece(socket, id, attrs) do
    with piece when not is_nil(piece) <- find_piece(socket.assigns.breakout, id),
         {:ok, _} <- Breakouts.update_piece(piece, attrs) do
      {:noreply, reload(socket)}
    else
      _ -> {:noreply, socket}
    end
  end

  defp current_position(event) do
    case event.presentation_file.presentation_state do
      %{position: position} when is_integer(position) -> position
      _ -> 0
    end
  end

  ## Display helpers

  @doc "A short line describing a piece: its title, or the start of its text."
  def piece_summary(%{kind: "text"} = piece, _content) do
    piece.body
    |> to_string()
    |> String.split("\n", trim: true)
    |> List.first("")
    |> String.slice(0, 120)
  end

  def piece_summary(_piece, %{title: title}) when is_binary(title), do: title
  def piece_summary(_piece, _content), do: ""

  def piece_label(piece), do: PieceType.module_for!(piece).label()
  def answerable?(piece), do: PieceType.module_for!(piece).answerable?()

  @doc "What an interaction editor in piece mode works on."
  def target(%{action: :new, packet: packet}), do: {:new, packet}
  def target(%{action: :edit, piece: piece}), do: {:edit, piece}

  def editor_title(%{action: action, kind: kind}) do
    label = PieceType.module_for(kind).label()

    case action do
      :new -> gettext("Add %{kind}", kind: String.downcase(label))
      :edit -> gettext("Edit %{kind}", kind: String.downcase(label))
    end
  end
end
