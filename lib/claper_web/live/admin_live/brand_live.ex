defmodule ClaperWeb.AdminLive.BrandLive do
  @moduledoc """
  Admin › Brand (docs/BRAND.md, 2026-11-14): whoever runs this app sets their
  organization's name, short mark, description, logo, mark, browser icon and
  sign-in photo here, and the link to their copy's source code, without
  changing code. Administrators only.

  Images upload as soon as they are chosen (or dropped) and replace the
  previous one; text is saved with each section's Save button.
  """
  use ClaperWeb, :admin_live_view

  alias Claper.Branding
  alias Claper.Branding.Brand

  on_mount(ClaperWeb.UserLiveAuth)

  @kinds [:logo, :mark, :icon, :photo]

  @impl true
  def mount(_params, session, socket) do
    with %{"locale" => locale} <- session do
      Gettext.put_locale(ClaperWeb.Gettext, locale)
    end

    if admin?(socket) do
      socket =
        Enum.reduce(@kinds, socket, fn kind, socket ->
          allow_upload(socket, kind,
            accept: Branding.accept(kind),
            max_entries: 1,
            max_file_size: Branding.max_size(kind),
            auto_upload: true,
            progress: &handle_progress/3
          )
        end)

      {:ok,
       socket
       |> assign(:page_title, gettext("Brand"))
       |> assign(:image_errors, %{})
       |> load()}
    else
      {:ok, redirect(socket, to: ~p"/")}
    end
  end

  @impl true
  def handle_params(_params, _url, socket), do: {:noreply, socket}

  defp load(socket) do
    brand = Branding.get()

    socket
    |> assign(:brand, brand)
    |> assign(:identity_form, to_form(Branding.change(brand), as: :brand))
    |> assign(:source_form, to_form(Branding.change(brand), as: :brand))
    |> assign(:privacy_form, to_form(Branding.change(brand), as: :brand))
  end

  @impl true
  def handle_event("validate_identity", %{"brand" => params}, socket) do
    changeset = socket.assigns.brand |> Branding.change(params) |> Map.put(:action, :validate)
    {:noreply, assign(socket, :identity_form, to_form(changeset, as: :brand))}
  end

  def handle_event("save_identity", %{"brand" => params}, socket) do
    params = Map.take(params, ["name", "monogram", "short_name", "description"])
    save(socket, params, :identity_form, gettext("Name and description saved"))
  end

  def handle_event("validate_source", %{"brand" => params}, socket) do
    changeset = socket.assigns.brand |> Branding.change(params) |> Map.put(:action, :validate)
    {:noreply, assign(socket, :source_form, to_form(changeset, as: :brand))}
  end

  def handle_event("save_source", %{"brand" => params}, socket) do
    save(
      socket,
      Map.take(params, ["source_url"]),
      :source_form,
      gettext("Source code link saved")
    )
  end

  def handle_event("validate_privacy", %{"brand" => params}, socket) do
    changeset = socket.assigns.brand |> Branding.change(params) |> Map.put(:action, :validate)
    {:noreply, assign(socket, :privacy_form, to_form(changeset, as: :brand))}
  end

  def handle_event("save_privacy", %{"brand" => params}, socket) do
    save(
      socket,
      Map.take(params, ["privacy_email"]),
      :privacy_form,
      gettext("Privacy contact saved")
    )
  end

  def handle_event("photo_position", %{"tab" => position}, socket) do
    save(socket, %{"photo_position" => position}, nil, gettext("Photo position saved"))
  end

  # The file inputs sit in forms (LiveView needs that); uploads save on
  # their own as soon as they finish (handle_progress/3).
  def handle_event("validate_upload", _params, socket), do: {:noreply, socket}

  def handle_event("cancel_upload", %{"kind" => kind, "ref" => ref}, socket) do
    {:noreply, cancel_upload(socket, kind_atom(kind), ref)}
  end

  def handle_event("remove_image", %{"kind" => kind}, socket) do
    case admin?(socket) && Branding.remove_image(kind_atom(kind)) do
      false ->
        {:noreply, not_allowed(socket)}

      {:ok, _} ->
        ClaperWeb.AuditContext.record(socket, "admin.brand_image_removed",
          metadata: %{image: kind}
        )

        {:noreply, socket |> load() |> put_flash(:info, gettext("Image removed"))}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, gettext("Could not remove the image"))}
    end
  end

  defp save(socket, params, form_key, message) do
    case admin?(socket) && Branding.update(params) do
      false ->
        {:noreply, not_allowed(socket)}

      {:ok, _brand} ->
        # Audit Log: which fields, and their new text
        ClaperWeb.AuditContext.record(socket, "admin.brand_updated", metadata: params)
        {:noreply, socket |> load() |> put_flash(:info, message)}

      {:error, changeset} when is_atom(form_key) and not is_nil(form_key) ->
        {:noreply, assign(socket, form_key, to_form(changeset, as: :brand))}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, gettext("Could not save"))}
    end
  end

  defp handle_progress(kind, entry, socket) do
    cond do
      not entry.done? ->
        {:noreply, socket}

      not admin?(socket) ->
        {:noreply, socket |> cancel_upload(kind, entry.ref) |> not_allowed()}

      true ->
        save_upload(kind, entry, socket)
    end
  end

  defp save_upload(kind, entry, socket) do
    result =
      consume_uploaded_entry(socket, entry, fn %{path: path} ->
        {:ok, Branding.put_image(kind, path, Path.extname(entry.client_name))}
      end)

    case result do
      {:ok, _brand} ->
        ClaperWeb.AuditContext.record(socket, "admin.brand_image_updated",
          metadata: %{image: Atom.to_string(kind)}
        )

        {:noreply,
         socket
         |> update(:image_errors, &Map.delete(&1, kind))
         |> load()
         |> put_flash(:info, gettext("Image saved"))}

      {:error, reason} ->
        {:noreply, update(socket, :image_errors, &Map.put(&1, kind, image_error(reason)))}
    end
  end

  # Checked again on every change, so someone whose admin role was removed
  # while this page was open cannot keep changing the brand.
  defp admin?(socket) do
    case socket.assigns[:current_user] do
      %Claper.Accounts.User{id: id} ->
        case Claper.Accounts.get_user(id) do
          nil -> false
          user -> Claper.Accounts.user_has_role?(user, "admin")
        end

      _ ->
        false
    end
  end

  defp not_allowed(socket) do
    socket
    |> put_flash(:error, gettext("Only administrators can change the brand"))
    |> redirect(to: ~p"/")
  end

  defp kind_atom(kind) when kind in ["logo", "mark", "icon", "photo"],
    do: String.to_existing_atom(kind)

  defp image_error(:type), do: gettext("This kind of file isn't accepted here.")

  defp image_error(:contents),
    do:
      gettext(
        "This file isn't a real image of the kind its name says. Export it again and retry."
      )

  defp image_error(_), do: gettext("The image could not be saved.")

  @doc """
  One image's upload area on the Brand page: the current image (or the
  default), drop or choose a file (it saves as soon as it arrives), and
  Remove.
  """
  attr :kind, :atom, required: true
  attr :upload, :any, required: true
  attr :current, :string, default: nil
  attr :error, :string, default: nil
  attr :hint, :string, required: true
  slot :preview, required: true

  def upload_zone(assigns) do
    ~H"""
    <form
      id={"brand-#{@kind}-form"}
      phx-change="validate_upload"
      phx-submit="validate_upload"
      class="flex flex-col gap-3"
    >
      <div
        class="rounded-2xl border-2 border-dashed border-base-300 bg-base-200/50 p-4"
        phx-drop-target={@upload.ref}
      >
        <div class="flex flex-col items-center gap-3 text-center">
          {render_slot(@preview)}
          <div :for={entry <- @upload.entries} class="w-full max-w-sm">
            <div class="flex items-center justify-between gap-2 text-sm text-muted">
              <span class="truncate">{entry.client_name}</span>
              <span class="tabular-nums">{entry.progress}%</span>
              <button
                type="button"
                class="btn btn-ghost btn-sm"
                phx-click="cancel_upload"
                phx-value-kind={@kind}
                phx-value-ref={entry.ref}
              >
                {gettext("Cancel")}
              </button>
            </div>
            <p :for={err <- upload_errors(@upload, entry)} class="text-sm text-error">
              {upload_error(err)}
            </p>
          </div>
          <p class="text-xs text-muted">{gettext("Drag and drop an image here, or")}</p>
          <div class="flex flex-wrap justify-center gap-2">
            <label for={@upload.ref} class="btn btn-outline btn-sm">
              {if @current, do: gettext("Replace image"), else: gettext("Choose image")}
            </label>
            <button
              :if={@current}
              type="button"
              class="btn btn-ghost btn-sm"
              phx-click="remove_image"
              phx-value-kind={@kind}
              data-confirm-title={gettext("Remove this image?")}
              data-confirm={gettext("The default shows in its place.")}
              data-confirm-action={gettext("Remove")}
              data-confirm-variant="destructive"
            >
              {gettext("Remove")}
            </button>
          </div>
        </div>
        <.live_file_input upload={@upload} class="sr-only" />
      </div>
      <p :for={err <- upload_errors(@upload)} class="text-sm text-error">{upload_error(err)}</p>
      <p :if={@error} class="text-sm text-error">{@error}</p>
      <p class="text-xs text-muted">{@hint}</p>
    </form>
    """
  end

  @doc false
  def upload_error(:too_large), do: gettext("The file is too large.")
  def upload_error(:not_accepted), do: gettext("This kind of file isn't accepted here.")
  def upload_error(:too_many_files), do: gettext("Choose one file.")
  def upload_error(_), do: gettext("The file could not be uploaded.")

  @doc false
  def megabytes(bytes), do: div(bytes, 1_000_000)

  @doc false
  def types(kind),
    do:
      kind
      |> Branding.accept()
      |> Enum.map_join(", ", &(&1 |> String.trim_leading(".") |> String.upcase()))

  @doc false
  def positions do
    [
      {"left", gettext("Left")},
      {"center", gettext("Center")},
      {"right", gettext("Right")}
    ]
  end

  @doc false
  def photo_position(%Brand{photo_position: p}) when is_binary(p), do: p
  def photo_position(_), do: "center"

  # Written out in full so Tailwind finds the classes.
  @doc false
  def object_position(brand) do
    case photo_position(brand) do
      "left" -> "object-left"
      "right" -> "object-right"
      _ -> "object-center"
    end
  end
end
