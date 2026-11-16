defmodule ClaperWeb.EventLive.MaterialsComponent do
  @moduledoc """
  The Materials card in the manage screen's settings (docs/MATERIALS.md,
  Jose 2026-11-15): two lists, **Handouts** (opened during the event) and
  **Take-home** (on the page after it), each item with its own switch.

  The card's **+** opens the add window (`MaterialsAddComponent`). The
  Take-home list also has the **Slides** switch and
  **Available until**, the date and time the take-home page closes (7 days
  after the event ends unless set).

  The card appears twice (the sidebar, and the settings window on smaller
  screens), so everything is per component; the manage screen refreshes
  both when materials change (`Claper.Materials.subscribe/1`).
  """
  use ClaperWeb, :live_component

  alias Claper.{Materials, Repo}
  alias Claper.Events.Event

  @impl true
  def update(%{event_id: event_id} = assigns, socket) do
    {:ok, socket |> assign(Map.drop(assigns, [:refresh])) |> load(event_id)}
  end

  def update(%{refresh: true}, socket), do: {:ok, load(socket, socket.assigns.event.id)}

  defp load(socket, event_id) do
    event = Repo.get!(Event, event_id)

    assign(socket,
      event: event,
      handouts: Materials.list_materials(event, "handout"),
      take_homes: Materials.list_materials(event, "take_home"),
      has_slides?: not is_nil(Materials.slides_path(event)),
      until: Materials.take_home_until(event),
      until_form: until_form(event, socket.assigns.id)
    )
  end

  # Ids prefixed per card: the card appears twice on the page
  defp until_form(event, id) do
    value =
      case Materials.take_home_until(event) do
        nil -> ""
        until -> NaiveDateTime.to_iso8601(until)
      end

    to_form(%{"take_home_until" => value}, as: :take_home, id: "#{id}-take-home")
  end

  # The window to add one sits at the top of the manage screen
  # (MaterialsAddComponent): this card also appears inside the settings
  # window, where a second window would be cut off.
  @impl true
  def handle_event("add", _params, socket) do
    send(self(), :open_materials_add)
    {:noreply, socket}
  end

  ## Changing

  def handle_event("toggle", %{"id" => id}, socket) do
    with %{} = material <- find(socket, id) do
      Materials.set_enabled(material, not material.enabled)
    end

    {:noreply, load(socket, socket.assigns.event.id)}
  end

  def handle_event("move", %{"id" => id, "direction" => direction}, socket)
      when direction in ["up", "down"] do
    with %{} = material <- find(socket, id) do
      Materials.move(material, String.to_existing_atom(direction))
    end

    {:noreply, load(socket, socket.assigns.event.id)}
  end

  def handle_event("delete", %{"id" => id}, socket) do
    with %{} = material <- find(socket, id) do
      Materials.delete_material(material)
    end

    {:noreply, load(socket, socket.assigns.event.id)}
  end

  def handle_event("toggle_slides", _params, socket) do
    %{event: event} = socket.assigns
    Materials.set_take_home_slides(event, not event.take_home_slides)
    {:noreply, load(socket, event.id)}
  end

  def handle_event("set_until", %{"take_home" => %{"take_home_until" => value}}, socket) do
    with {:ok, until} <- NaiveDateTime.from_iso8601(value),
         {:ok, _} <- Materials.set_take_home_until(socket.assigns.event, until) do
      {:noreply, load(socket, socket.assigns.event.id)}
    else
      {:error, :before_start} ->
        {:noreply,
         socket
         |> load(socket.assigns.event.id)
         |> ClaperWeb.Toast.push(:error, gettext("Choose a time after the event starts."))}

      _ ->
        {:noreply, socket}
    end
  end

  def handle_event("set_until", _params, socket), do: {:noreply, socket}

  defp find(socket, id),
    do: Enum.find(socket.assigns.handouts ++ socket.assigns.take_homes, &(&1.uuid == id))

  @doc false
  def size(bytes) when bytes >= 1_000_000,
    do: "#{:erlang.float_to_binary(bytes / 1_000_000, decimals: 1)} MB"

  def size(bytes), do: "#{max(div(bytes, 1000), 1)} KB"

  ## The card

  @impl true
  def render(assigns) do
    ~H"""
    <div id={@id} class="panel">
      <div class="panel-header">
        <svg
          class="size-5 shrink-0 text-base-content"
          viewBox="0 0 24 24"
          fill="none"
          stroke="currentColor"
          stroke-width="2"
          stroke-linecap="round"
          stroke-linejoin="round"
          aria-hidden="true"
        >
          <path d="M14 3v4a1 1 0 0 0 1 1h4" />
          <path d="M17 21h-10a2 2 0 0 1 -2 -2v-14a2 2 0 0 1 2 -2h7l5 5v11a2 2 0 0 1 -2 2z" />
          <path d="M9 13h6" />
          <path d="M9 17h4" />
        </svg>
        <span class="text-sm font-bold text-base-content">{gettext("Materials")}</span>
        <button
          type="button"
          phx-click="add"
          phx-target={@myself}
          aria-label={gettext("Add material")}
          data-tooltip={gettext("Add material")}
          class="btn btn-ghost btn-circle btn-sm ml-auto"
        >
          <svg class="size-5" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
            <path stroke-linecap="round" d="M12 5v14M5 12h14" />
          </svg>
        </button>
      </div>

      <div class="flex flex-col gap-4 px-1">
        <section class="flex flex-col gap-2">
          <h3 class="text-xs font-bold uppercase tracking-wide text-muted">{gettext("Handouts")}</h3>
          <p :if={@handouts == []} class="text-sm text-muted">
            {gettext("PDFs people open during the event. None yet.")}
          </p>
          <.item :for={m <- @handouts} material={m} myself={@myself} id={@id} />
        </section>

        <section class="flex flex-col gap-2">
          <h3 class="text-xs font-bold uppercase tracking-wide text-muted">
            {gettext("Take-home")}
          </h3>
          <label class="switch-card">
            <div class="flex min-w-0 flex-1 flex-col gap-0.5 leading-snug">
              <span class="text-sm font-medium text-base-content">{gettext("Slides")}</span>
              <span class="text-sm text-muted">
                {if @has_slides?,
                  do: gettext("The presentation as a PDF"),
                  else: gettext("No PDF of these slides")}
              </span>
            </div>
            <ClaperWeb.Component.Switch.switch
              checked={@event.take_home_slides}
              disabled={not @has_slides?}
              aria-label={gettext("Slides")}
              phx-click="toggle_slides"
              phx-target={@myself}
            />
          </label>
          <.item :for={m <- @take_homes} material={m} myself={@myself} id={@id} />
          <p :if={@take_homes == []} class="text-sm text-muted">
            {gettext("PDFs on the page people get after the event. None yet.")}
          </p>

          <.form
            for={@until_form}
            id={"#{@id}-until"}
            phx-change="set_until"
            phx-target={@myself}
            class="flex flex-col gap-1 pt-1"
          >
            <ClaperWeb.Component.Input.date
              form={@until_form}
              key={:take_home_until}
              name={gettext("Available until")}
            />
            <p class="text-xs text-muted">
              {if @event.take_home_until,
                do: gettext("Shown in your local time. The take-home page closes then."),
                else:
                  if(@until,
                    do: gettext("7 days after the event ended. Shown in your local time."),
                    else: gettext("7 days after the event ends, unless you choose a time.")
                  )}
            </p>
          </.form>
        </section>
      </div>
    </div>
    """
  end

  attr :material, :map, required: true
  attr :myself, :any, required: true
  attr :id, :string, required: true

  defp item(assigns) do
    ~H"""
    <div id={"#{@id}-#{@material.uuid}"} class="switch-card items-start">
      <div class="flex min-w-0 flex-1 flex-col gap-1 leading-snug">
        <span class="truncate text-sm font-medium text-base-content" title={@material.title}>
          {@material.title}
        </span>
        <span class="text-xs text-muted">{size(@material.byte_size)}</span>
        <div class="flex items-center gap-1">
          <button
            type="button"
            phx-click="move"
            phx-value-id={@material.uuid}
            phx-value-direction="up"
            phx-target={@myself}
            aria-label={gettext("Move up")}
            data-tooltip={gettext("Move up")}
            class="btn btn-ghost btn-xs btn-square"
          >
            <svg class="size-4" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
              <path stroke-linecap="round" stroke-linejoin="round" d="m6 15 6-6 6 6" />
            </svg>
          </button>
          <button
            type="button"
            phx-click="move"
            phx-value-id={@material.uuid}
            phx-value-direction="down"
            phx-target={@myself}
            aria-label={gettext("Move down")}
            data-tooltip={gettext("Move down")}
            class="btn btn-ghost btn-xs btn-square"
          >
            <svg class="size-4" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
              <path stroke-linecap="round" stroke-linejoin="round" d="m6 9 6 6 6-6" />
            </svg>
          </button>
          <a
            href={~p"/materials/#{@material.uuid}"}
            aria-label={gettext("Download")}
            data-tooltip={gettext("Download")}
            class="btn btn-ghost btn-xs btn-square"
          >
            <svg class="size-4" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
              <path
                stroke-linecap="round"
                stroke-linejoin="round"
                d="M12 4v12m0 0-4-4m4 4 4-4M5 20h14"
              />
            </svg>
          </a>
          <button
            type="button"
            phx-click="delete"
            phx-value-id={@material.uuid}
            phx-target={@myself}
            aria-label={gettext("Remove")}
            data-tooltip={gettext("Remove")}
            data-confirm-title={gettext("Remove this PDF?")}
            data-confirm={gettext("People won't be able to open or download it any more.")}
            data-confirm-action={gettext("Remove")}
            class="btn btn-ghost btn-xs btn-square text-error"
          >
            <svg class="size-4" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
              <path
                stroke-linecap="round"
                stroke-linejoin="round"
                d="M4 7h16M10 11v6M14 11v6M5 7l1 12a2 2 0 0 0 2 2h8a2 2 0 0 0 2-2l1-12M9 7V4h6v3"
              />
            </svg>
          </button>
        </div>
      </div>
      <ClaperWeb.Component.Switch.switch
        checked={@material.enabled}
        aria-label={gettext("Show %{title}", title: @material.title)}
        phx-click="toggle"
        phx-value-id={@material.uuid}
        phx-target={@myself}
      />
    </div>
    """
  end
end
