defmodule ClaperWeb.EventLive.MaterialsAddComponent do
  @moduledoc """
  The window to add a handout or take-home PDF (docs/MATERIALS.md, Jose
  2026-11-15): choose Handout or Take-home, then upload a PDF and give it a
  title (a handout can also go to Take-home, as a separate item with its own
  switch).

  One per manage screen, at its top level, opened by either Materials card
  (`MaterialsComponent` sends `:open_materials_add`; the manage screen
  passes `open: true`). Inside the settings window a nested window would be
  cut off. The cards refresh from the materials channel once a file is added.
  """
  use ClaperWeb, :live_component

  alias Claper.{Materials, Repo}
  alias Claper.Events.Event

  @impl true
  def mount(socket) do
    {:ok,
     socket
     |> assign(adding: nil, error: nil, title: "", also_take_home: false)
     |> allow_upload(:pdf,
       accept: ~w(.pdf),
       max_entries: 1,
       max_file_size: Materials.max_bytes()
     )}
  end

  @impl true
  def update(%{open: true}, socket),
    do: {:ok, assign(socket, adding: :choose, error: nil, title: "", also_take_home: false)}

  def update(assigns, socket), do: {:ok, assign(socket, assigns)}

  @impl true
  def handle_event("choose", %{"kind" => kind}, socket) when kind in ["handout", "take_home"],
    do: {:noreply, assign(socket, adding: kind, title: "", also_take_home: false, error: nil)}

  def handle_event("close", _params, socket) do
    socket =
      Enum.reduce(socket.assigns.uploads.pdf.entries, socket, fn entry, acc ->
        cancel_upload(acc, :pdf, entry.ref)
      end)

    {:noreply, assign(socket, adding: nil, error: nil)}
  end

  def handle_event("validate", %{"material" => params}, socket) do
    title = params["title"] || ""

    # A title from the file's name when none is typed yet
    title =
      case {String.trim(title), socket.assigns.uploads.pdf.entries} do
        {"", [entry | _]} -> entry.client_name |> Path.rootname() |> String.slice(0, 120)
        _ -> title
      end

    {:noreply,
     assign(socket, title: title, also_take_home: params["also_take_home"] == "true", error: nil)}
  end

  def handle_event("cancel_pdf", %{"ref" => ref}, socket),
    do: {:noreply, cancel_upload(socket, :pdf, ref)}

  def handle_event("save", %{"material" => params}, socket) do
    %{event_id: event_id, adding: kind} = socket.assigns
    event = Repo.get!(Event, event_id)
    title = String.trim(params["title"] || "")
    also = kind == "handout" and params["also_take_home"] == "true"

    cond do
      socket.assigns.uploads.pdf.entries == [] ->
        {:noreply, assign(socket, error: gettext("Choose a PDF to upload."), title: title)}

      title == "" ->
        {:noreply, assign(socket, error: gettext("Give it a title."), title: title)}

      true ->
        results =
          consume_uploaded_entries(socket, :pdf, fn %{path: path}, entry ->
            attrs = %{kind: kind, title: title, original_name: entry.client_name}
            {:ok, Materials.create_material(event, attrs, path, also_take_home: also)}
          end)

        case results do
          [{:ok, _}] ->
            {:noreply,
             socket
             |> assign(adding: nil, error: nil)
             |> then(&ClaperWeb.Toast.push(&1, :success, saved_message(kind, also)))}

          [{:error, reason}] ->
            {:noreply, assign(socket, error: error_message(reason), title: title)}

          _ ->
            {:noreply, assign(socket, error: gettext("Choose a PDF to upload."), title: title)}
        end
    end
  end

  defp saved_message("handout", true), do: gettext("Added to Handouts and Take-home")
  defp saved_message("handout", _), do: gettext("Added to Handouts")
  defp saved_message(_, _), do: gettext("Added to Take-home")

  @doc false
  def error_message(:not_pdf), do: gettext("That file isn't a PDF.")
  def error_message(:too_large), do: gettext("That PDF is larger than 25 MB.")
  def error_message(:empty), do: gettext("That file is empty.")
  def error_message(:storage), do: gettext("This server can't store files for events.")
  def error_message(%Ecto.Changeset{}), do: gettext("Give it a title of up to 120 characters.")
  def error_message(_), do: gettext("That file couldn't be uploaded.")

  @doc false
  def upload_error(:too_large), do: gettext("That PDF is larger than 25 MB.")
  def upload_error(:not_accepted), do: gettext("Choose a PDF file.")
  def upload_error(:too_many_files), do: gettext("Choose one file.")
  def upload_error(_), do: gettext("That file couldn't be uploaded.")

  @impl true
  def render(assigns) do
    ~H"""
    <div id={@id}>
      <div
        :if={@adding}
        id={"#{@id}-window"}
        class="modal manage-modal modal-open"
        role="dialog"
        aria-modal="true"
        aria-labelledby={"#{@id}-title"}
      >
        <div class="modal-box max-w-lg">
          <button
            type="button"
            phx-click="close"
            phx-target={@myself}
            aria-label={gettext("Close")}
            class="btn btn-sm btn-circle btn-ghost absolute right-2 top-2"
          >
            &times;
          </button>

          <div :if={@adding == :choose} class="flex flex-col gap-2">
            <h2 id={"#{@id}-title"} class="text-lg font-bold text-base-content">
              {gettext("Add material")}
            </h2>
            <button
              type="button"
              phx-click="choose"
              phx-value-kind="handout"
              phx-target={@myself}
              class="menu-item group select-none items-start p-3 text-left"
            >
              <div class="flex-auto">
                <p class="font-medium text-base-content">{gettext("Handout")}</p>
                <p class="text-sm text-muted">
                  {gettext("A PDF people open during the event, from the page icon.")}
                </p>
              </div>
            </button>
            <button
              type="button"
              phx-click="choose"
              phx-value-kind="take_home"
              phx-target={@myself}
              class="menu-item group select-none items-start p-3 text-left"
            >
              <div class="flex-auto">
                <p class="font-medium text-base-content">{gettext("Take-home")}</p>
                <p class="text-sm text-muted">
                  {gettext("A PDF people download from the page they get after the event.")}
                </p>
              </div>
            </button>
          </div>

          <.form
            :let={f}
            :if={@adding in ["handout", "take_home"]}
            for={to_form(%{"title" => @title, "also_take_home" => @also_take_home}, as: :material)}
            id={"#{@id}-form"}
            phx-change="validate"
            phx-submit="save"
            phx-target={@myself}
            class="flex flex-col gap-4"
          >
            <h2 id={"#{@id}-title"} class="text-lg font-bold text-base-content">
              {if @adding == "handout", do: gettext("Add a handout"), else: gettext("Add take-home")}
            </h2>

            <div
              class="rounded-2xl border-2 border-dashed border-base-300 bg-base-200/50 p-4"
              phx-drop-target={@uploads.pdf.ref}
            >
              <div :for={entry <- @uploads.pdf.entries} class="flex flex-col gap-1">
                <div class="flex items-center justify-between gap-2 text-sm">
                  <span class="truncate text-base-content">{entry.client_name}</span>
                  <button
                    type="button"
                    class="btn btn-ghost btn-sm"
                    phx-click="cancel_pdf"
                    phx-value-ref={entry.ref}
                    phx-target={@myself}
                  >
                    {gettext("Remove")}
                  </button>
                </div>
                <progress class="progress w-full" value={entry.progress} max="100"></progress>
                <p :for={err <- upload_errors(@uploads.pdf, entry)} class="text-sm text-error">
                  {upload_error(err)}
                </p>
              </div>
              <div
                :if={@uploads.pdf.entries == []}
                class="flex flex-col items-center gap-2 text-center"
              >
                <p class="text-xs text-muted">{gettext("Drag and drop a PDF here, or")}</p>
                <label for={@uploads.pdf.ref} class="btn btn-outline btn-sm">
                  {gettext("Choose PDF")}
                </label>
                <p class="text-xs text-muted">{gettext("Up to 25 MB.")}</p>
              </div>
              <.live_file_input upload={@uploads.pdf} class="sr-only" />
            </div>
            <p :for={err <- upload_errors(@uploads.pdf)} class="text-sm text-error">
              {upload_error(err)}
            </p>

            <label class="flex flex-col gap-1">
              <span class="text-sm font-bold text-base-content">{gettext("Title")}</span>
              <input type="text" name="material[title]" value={@title} maxlength="120" class="input" />
              <span class="text-xs text-muted">{gettext("What people see in the list.")}</span>
            </label>

            <ClaperWeb.Component.Checkbox.checkbox
              :if={@adding == "handout"}
              form={f}
              key={:also_take_home}
              label={gettext("Also add to Take-home (it gets its own switch)")}
            />

            <p :if={@error} class="text-sm text-error" role="alert">{@error}</p>

            <div class="flex justify-end gap-2">
              <button type="button" class="btn btn-ghost" phx-click="close" phx-target={@myself}>
                {gettext("Cancel")}
              </button>
              <button type="submit" class="btn btn-primary" phx-disable-with={gettext("Adding...")}>
                {gettext("Add")}
              </button>
            </div>
          </.form>
        </div>
        <div class="modal-backdrop" phx-click="close" phx-target={@myself}></div>
      </div>
    </div>
    """
  end
end
