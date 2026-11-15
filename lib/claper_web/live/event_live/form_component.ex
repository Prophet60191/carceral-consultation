defmodule ClaperWeb.EventLive.FormComponent do
  use ClaperWeb, :live_component

  @impl true
  def render(assigns) do
    assigns = assign_new(assigns, :focus_mode, fn -> false end)

    ~H"""
    <div class="font-display">
      <div
        :if={!@focus_mode}
        id="collapsed-form"
        class="mx-auto hidden w-max rounded-full bg-base-100 px-5 py-3 shadow-xl ring-1 ring-line"
      >
        <button
          type="button"
          class="pressable block h-full w-full"
          phx-click={toggle_form()}
          phx-target={@myself}
        >
          <div class="flex items-center gap-2 text-base-content">
            <svg
              xmlns="http://www.w3.org/2000/svg"
              class="h-5 w-5 text-primary"
              viewBox="0 0 24 24"
              stroke-width="1.5"
              stroke="currentColor"
              fill="none"
              stroke-linecap="round"
              stroke-linejoin="round"
            >
              <path stroke="none" d="M0 0h24v24H0z" fill="none"></path>
              <path d="M12 3a3 3 0 0 0 -3 3v12a3 3 0 0 0 3 3"></path>
              <path d="M6 3a3 3 0 0 1 3 3v12a3 3 0 0 1 -3 3"></path>
              <path d="M13 7h7a1 1 0 0 1 1 1v8a1 1 0 0 1 -1 1h-7"></path>
              <path d="M5 7h-1a1 1 0 0 0 -1 1v8a1 1 0 0 0 1 1h1"></path>
              <path d="M17 12h.01"></path>
              <path d="M13 12h.01"></path>
            </svg>
            <span class="text-sm font-bold">{gettext("See current form")}</span>
          </div>
        </button>
      </div>
      <div
        id="extended-form"
        class={[
          "w-full rounded-2xl bg-base-100 p-4 text-base-content",
          @focus_mode && "shadow-none ring-0",
          !@focus_mode && "shadow-2xl ring-1 ring-line"
        ]}
      >
        <div class="relative pr-8">
          <button
            :if={!@focus_mode}
            id="form-pane"
            type="button"
            aria-label={gettext("Close")}
            class="btn btn-ghost btn-circle btn-sm absolute -right-1 -top-1 text-muted"
            phx-click={toggle_form()}
            phx-target={@myself}
          >
            <svg
              xmlns="http://www.w3.org/2000/svg"
              class="h-5 w-5"
              fill="none"
              viewBox="0 0 24 24"
              stroke="currentColor"
              stroke-width="2"
            >
              <path stroke-linecap="round" stroke-linejoin="round" d="M6 18L18 6M6 6l12 12" />
            </svg>
          </button>

          <p class="mb-1 text-xs font-semibold text-muted">{gettext("Current form")}</p>
          <p class="mb-4 text-lg font-bold leading-snug text-base-content">{@form.title}</p>
        </div>
        <%= form_for :form_submit, "#", [id: @id, phx_change: "validate", phx_target: @myself, phx_submit: "submit"], fn f -> %>
          <div class="flex flex-col gap-3">
            <%= if (length @form.fields) > 0 do %>
              <%= for field <- @form.fields do %>
                <%= case field.type do %>
                  <% "text" -> %>
                    <ClaperWeb.Component.Input.text
                      form={f}
                      labelClass="text-muted"
                      key={field_key(field.name)}
                      name={field.name}
                      required={field.required}
                      readonly={not is_nil(assigns.current_form_submit)}
                      value={
                        if is_nil(assigns.current_form_submit),
                          do: ~c"",
                          else: assigns.current_form_submit.response[field.name]
                      }
                    />
                  <% "email" -> %>
                    <ClaperWeb.Component.Input.email
                      form={f}
                      labelClass="text-muted"
                      key={field_key(field.name)}
                      name={field.name}
                      required={field.required}
                      readonly={not is_nil(assigns.current_form_submit)}
                      value={
                        if is_nil(assigns.current_form_submit),
                          do: ~c"",
                          else: assigns.current_form_submit.response[field.name]
                      }
                    />
                <% end %>
              <% end %>
            <% end %>
          </div>

          <div class="mt-4">
            <%= if is_nil(assigns.current_form_submit) do %>
              <button type="submit" class="btn btn-primary w-full">
                {gettext("Send")}
              </button>
            <% else %>
              <button
                type="button"
                disabled
                data-submitted
                class="btn btn-secondary btn-disabled w-full"
              >
                <svg
                  xmlns="http://www.w3.org/2000/svg"
                  class="h-5 w-5"
                  viewBox="0 0 24 24"
                  fill="none"
                  stroke="currentColor"
                  stroke-width="2"
                  stroke-linecap="round"
                  stroke-linejoin="round"
                  aria-hidden="true"
                >
                  <path stroke="none" d="M0 0h24v24H0z" fill="none" />
                  <path d="M5 12l5 5l10 -10" />
                </svg>
                {gettext("Sent")}
              </button>
            <% end %>
          </div>
        <% end %>
      </div>
    </div>
    """
  end

  @impl true
  def handle_event("validate", %{"form_submit" => form_submit_params}, socket) do
    changeset =
      (socket.assigns.current_form_submit || %Claper.Forms.FormSubmit{})
      |> Claper.Forms.change_form_submit(form_submit_params)
      |> Map.put(:action, :validate)

    {:noreply, socket |> assign(:changeset, changeset)}
  end

  @impl true
  def handle_event(
        "submit",
        %{"form_submit" => params},
        %{assigns: %{current_user: current_user}} = socket
      )
      when is_map(current_user) do
    case Claper.Forms.create_or_update_form_submit(
           socket.assigns.event.uuid,
           %{"response" => params}
           |> Map.put("user_id", socket.assigns.current_user.id)
           |> Map.put("form_id", socket.assigns.form.id)
         ) do
      {:ok, form_submit} ->
        ClaperWeb.SecurityAudit.observe(
          socket,
          "form",
          socket.assigns.form.id,
          "submission_burst",
          20
        )

        {:noreply,
         socket
         |> assign(:current_form_submit, form_submit)}

      {:error, changeset} ->
        if match?(%Ecto.Changeset{}, changeset) do
          ClaperWeb.SecurityAudit.observe(
            socket,
            "form",
            socket.assigns.form.id,
            "validation_rejected"
          )
        end

        {:noreply, socket}
    end
  end

  @impl true
  def handle_event(
        "submit",
        %{"form_submit" => params},
        %{assigns: %{attendee_identifier: attendee_identifier}} = socket
      ) do
    case Claper.Forms.create_or_update_form_submit(
           socket.assigns.event.uuid,
           %{"response" => params}
           |> Map.put("attendee_identifier", attendee_identifier)
           |> Map.put("form_id", socket.assigns.form.id)
         ) do
      {:ok, form_submit} ->
        ClaperWeb.SecurityAudit.observe(
          socket,
          "form",
          socket.assigns.form.id,
          "submission_burst",
          20
        )

        {:noreply,
         socket
         |> assign(:current_form_submit, form_submit)}

      {:error, changeset} ->
        if match?(%Ecto.Changeset{}, changeset) do
          ClaperWeb.SecurityAudit.observe(
            socket,
            "form",
            socket.assigns.form.id,
            "validation_rejected"
          )
        end

        {:noreply, socket}
    end
  end

  defp field_key(name) when is_binary(name) do
    try do
      String.to_existing_atom(name)
    rescue
      ArgumentError -> String.to_atom(name)
    end
  end

  def toggle_form(js \\ %JS{}) do
    js
    |> JS.toggle(
      out: "animate__animated animate__zoomOut",
      in: "animate__animated animate__zoomIn",
      to: "#collapsed-form",
      time: 50
    )
    |> JS.toggle(
      out: "animate__animated animate__zoomOut",
      in: "animate__animated animate__zoomIn",
      to: "#extended-form"
    )
  end
end
