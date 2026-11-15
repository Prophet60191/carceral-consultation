defmodule ClaperWeb.AdminLive.UserLive.FormComponent do
  @moduledoc """
  Inviting someone (`:new`) and editing an account (`:edit`) in Admin › Users
  (docs/SECURITY.md, "Managing accounts").

  - Inviting sends an email; the person chooses their own password. There
    is no password field: administrators never set or see passwords.
  - Editing: names change at once. A new role is checked against the guards
    (`Claper.Accounts.Administration.check/3`) and signs the person out
    everywhere. A new email address is confirmed by its owner first (for
    an invitation nobody accepted yet, it's corrected and re-sent).
  - Saving needs a recent sign-in, and every change goes to the Audit Log.
  """
  use ClaperWeb, :live_component

  alias Claper.Accounts
  alias Claper.Accounts.Administration

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <.form for={@form} id="user-form" phx-target={@myself} phx-change="validate" phx-submit="save">
        <p :if={@action == :new} class="mb-6 text-sm text-muted">
          {gettext(
            "They'll get an email with a link to choose their own password. The link works for 7 days."
          )}
        </p>

        <div class="grid grid-cols-6 gap-6">
          <.live_component
            module={ClaperWeb.AdminLive.FormFieldComponent}
            id="user-first-name"
            form={@form}
            field={:first_name}
            type="text"
            label={gettext("First name")}
            placeholder={gettext("Enter first name")}
            required={true}
            width_class="sm:col-span-3"
          />

          <.live_component
            module={ClaperWeb.AdminLive.FormFieldComponent}
            id="user-last-name"
            form={@form}
            field={:last_name}
            type="text"
            label={gettext("Last name")}
            placeholder={gettext("Enter last name")}
            required={true}
            width_class="sm:col-span-3"
          />

          <.live_component
            module={ClaperWeb.AdminLive.FormFieldComponent}
            id="user-email"
            form={@form}
            field={:email}
            type="email"
            label={gettext("Email")}
            placeholder={gettext("Enter user email")}
            required={true}
            width_class="sm:col-span-6"
            description={
              if @action == :edit,
                do:
                  gettext(
                    "If you change it, a confirmation link goes to the new address. It changes when its owner opens the link."
                  ),
                else: nil
            }
          />

          <div :if={@editing_self} class="sm:col-span-6">
            <p class="text-sm font-medium text-base-content">{gettext("Role")}</p>
            <p id="own-role" class="mt-1 text-sm text-muted">
              {Administration.role_label(@user)}. {gettext(
                "You can't change your own role. Another administrator can."
              )}
            </p>
          </div>

          <.live_component
            :if={!@editing_self}
            module={ClaperWeb.AdminLive.FormFieldComponent}
            id="user-role-id"
            form={@form}
            field={:role_id}
            type="select"
            label={gettext("Role")}
            select_options={@role_options}
            required={true}
            width_class="sm:col-span-3"
            description={
              gettext(
                "Facilitators run their own events and the ones they're added to. Administrators also manage the app."
              )
            }
          />
        </div>

        <div class="pt-6">
          <div class="flex justify-end gap-3">
            <button type="button" phx-click="cancel" phx-target={@myself} class="btn btn-ghost">
              {gettext("Cancel")}
            </button>
            <button type="submit" phx-disable-with={gettext("Saving...")} class="btn btn-primary">
              {if @action == :new, do: gettext("Send invitation"), else: gettext("Save changes")}
            </button>
          </div>
        </div>
      </.form>
    </div>
    """
  end

  @impl true
  def update(%{user: user} = assigns, socket) do
    user = Claper.Repo.preload(user, :role)

    {:ok,
     socket
     |> assign(assigns)
     |> assign(:user, user)
     |> assign(:role_options, Administration.role_options())
     |> assign(
       :editing_self,
       assigns.action == :edit and not is_nil(assigns[:actor]) and assigns.actor.id == user.id
     )
     |> assign_form(Accounts.change_user(user, %{}, require_names: true))}
  end

  @impl true
  def handle_event("validate", %{"user" => user_params}, socket) do
    changeset =
      socket.assigns.user
      |> Accounts.change_user(user_params, require_names: true)
      |> Map.put(:action, :validate)

    {:noreply, assign_form(socket, changeset)}
  end

  def handle_event("save", %{"user" => user_params}, socket) do
    # Needs a recent sign-in (docs/SECURITY.md); the form may have been open
    # a long time
    if ClaperWeb.UserAuth.recently_signed_in?(socket.assigns[:signed_in_at]) do
      save_user(socket, socket.assigns.action, user_params)
    else
      return_to =
        if socket.assigns.action == :edit,
          do: ~p"/admin/users/#{socket.assigns.user}/edit",
          else: ~p"/admin/users/new"

      {:noreply, redirect(socket, to: ClaperWeb.UserAuth.confirm_password_path(return_to))}
    end
  end

  def handle_event("cancel", _params, socket) do
    {:noreply, push_navigate(socket, to: socket.assigns.navigate)}
  end

  defp save_user(socket, :new, params) do
    case Administration.invite(params, &url(~p"/users/invitation/#{&1}")) do
      {:ok, user} ->
        user = Claper.Repo.preload(user, :role)
        audit(socket, "admin.user_invited", user, %{role: role_name(user)})
        notify_parent({:saved, user})

        {:noreply,
         socket
         |> put_flash(:info, gettext("Invitation sent to %{email}.", email: user.email))
         |> push_navigate(to: ~p"/admin/users/#{user}")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign_form(socket, changeset)}
    end
  end

  defp save_user(socket, :edit, params) do
    before = socket.assigns.user
    actor = socket.assigns[:actor]
    role_change? = role_change?(before, params["role_id"]) and not socket.assigns.editing_self
    email_change? = is_binary(params["email"]) and String.trim(params["email"]) != before.email

    with :ok <- check_role(actor, before, role_change?, params["role_id"]),
         {:ok, updated} <- update_names_and_role(before, params, role_change?),
         {:ok, email_note} <- maybe_change_email(socket, updated, email_change?, params["email"]) do
      updated = Claper.Repo.preload(updated, :role, force: true)
      audit_edit(socket, before, updated)

      if role_change? do
        audit(socket, "admin.user_role_changed", updated, %{
          from: role_name(before),
          to: role_name(updated)
        })

        # The new role applies now, not at their next sign-in
        Administration.sign_out_everywhere(updated)
      end

      notify_parent({:saved, updated})

      {:noreply,
       socket
       |> put_flash(
         :info,
         Enum.join([gettext("Changes saved."), email_note], " ") |> String.trim()
       )
       |> push_navigate(to: ~p"/admin/users/#{updated}")}
    else
      {:error, reason} when is_binary(reason) ->
        {:noreply, put_flash(socket, :error, reason)}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign_form(socket, Map.put(changeset, :action, :validate))}
    end
  end

  defp role_change?(%{role_id: current}, new) when new not in [nil, ""],
    do: to_string(current) != to_string(new)

  defp role_change?(_, _), do: false

  defp check_role(_actor, _user, false, _role_id), do: :ok

  defp check_role(actor, user, true, role_id),
    do: Administration.check(actor, user, {:set_role, role_id})

  defp update_names_and_role(user, params, role_change?) do
    keys = ["first_name", "last_name"] ++ if(role_change?, do: ["role_id"], else: [])
    Accounts.update_user(user, Map.take(params, keys), require_names: true)
  end

  defp maybe_change_email(_socket, _user, false, _email), do: {:ok, ""}

  defp maybe_change_email(socket, user, true, email) do
    case Administration.change_email(
           user,
           String.trim(email),
           &url(~p"/users/settings/confirm_email/#{&1}"),
           &url(~p"/users/invitation/#{&1}")
         ) do
      {:ok, :invitation_resent, updated} ->
        audit(socket, "admin.invitation_email_corrected", updated, %{old_email: user.email})

        {:ok, gettext("The invitation was sent again to %{email}.", email: updated.email)}

      {:ok, :confirmation_sent, _user} ->
        audit(socket, "admin.email_change_sent", user, %{new_email: String.trim(email)})

        {:ok,
         gettext(
           "A confirmation link went to %{email}; the address changes when its owner opens it.",
           email: String.trim(email)
         )}

      {:error, changeset} ->
        {:error, changeset}
    end
  end

  # Audit Log (docs/SECURITY.md): what changed
  defp audit_edit(socket, before, after_) do
    changed =
      for field <- [:first_name, :last_name],
          Map.get(before, field) != Map.get(after_, field),
          do: Atom.to_string(field)

    if changed != [] do
      audit(socket, "admin.user_updated", after_, %{fields: Enum.join(changed, ", ")})
    end
  end

  defp role_name(%{role: %{name: name}}), do: name
  defp role_name(_), do: nil

  defp audit(socket, action, target, metadata) do
    Claper.Audit.record(socket.assigns[:actor], action,
      target: target,
      metadata: metadata,
      context: %{ip_address: socket.assigns[:client_ip]}
    )
  end

  defp assign_form(socket, %Ecto.Changeset{} = changeset) do
    assign(socket, :form, to_form(changeset, as: :user))
  end

  defp notify_parent(msg), do: send(self(), {__MODULE__, msg})
end
