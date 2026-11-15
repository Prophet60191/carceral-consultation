defmodule ClaperWeb.UserSettingsLive.Show do
  use ClaperWeb, :live_view

  alias Claper.Accounts

  on_mount(ClaperWeb.UserLiveAuth)
  on_mount(ClaperWeb.ReturnContextHook)

  @impl true
  def mount(_params, session, socket) do
    with %{"locale" => locale} <- session do
      Gettext.put_locale(ClaperWeb.Gettext, locale)
    end

    email_changeset = Accounts.User.email_changeset(%Accounts.User{}, %{})
    password_changeset = Accounts.User.password_changeset(%Accounts.User{}, %{})
    profile_changeset = Accounts.change_user_profile(socket.assigns.current_user)

    oidc_accounts =
      Accounts.get_all_oidc_users_by_email(socket.assigns.current_user.email) |> List.wrap()

    lti_accounts =
      Lti13.Users.get_all_users_by_user_id(socket.assigns.current_user.id)

    preferences_changeset =
      Accounts.User.preferences_changeset(
        socket.assigns.current_user,
        set_locale(socket.assigns.current_user)
      )

    {:ok,
     socket
     |> assign(:email_changeset, email_changeset)
     |> assign(:password_changeset, password_changeset)
     |> assign(:profile_changeset, profile_changeset)
     |> assign(:preferences_changeset, preferences_changeset)
     |> assign(:is_external_user, oidc_accounts != [] or lti_accounts != [])
     |> assign(:oidc_accounts, oidc_accounts)
     |> assign(:lti_accounts, lti_accounts)
     |> assign(
       :allow_unlink_external_provider,
       Application.get_env(:claper, :allow_unlink_external_provider)
     )}
  end

  @impl true
  def handle_params(_params, _url, %{assigns: %{live_action: :edit_email}} = socket) do
    # Changing the email address needs a recent sign-in (docs/SECURITY.md)
    if ClaperWeb.UserAuth.recently_signed_in?(socket) do
      {:noreply, apply_action(socket, :edit_email, %{})}
    else
      {:noreply,
       redirect(socket,
         to: ClaperWeb.UserAuth.confirm_password_path(~p"/users/settings/edit/email")
       )}
    end
  end

  def handle_params(params, _url, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :edit_email, _params) do
    socket
    |> assign(:page_title, gettext("Update your email"))
    |> assign(
      :page_description,
      gettext("Change the email address you want associated with your account.")
    )
  end

  defp apply_action(socket, :edit_profile, _params) do
    socket
    |> assign(:page_title, gettext("Update your profile"))
    |> assign(
      :page_description,
      gettext("Change the first and last name associated with your account.")
    )
  end

  defp apply_action(socket, :edit_password, _params) do
    socket
    |> assign(:page_title, gettext("Update your password"))
    |> assign(
      :page_description,
      gettext("Change the password used to access your account.")
    )
  end

  defp apply_action(socket, :set_password, _params) do
    socket
    |> assign(:page_title, gettext("Set a new password"))
    |> assign(
      :page_description,
      gettext("Set a new password for your account before unlinking it.")
    )
  end

  defp apply_action(socket, :show, _params) do
    socket
    |> assign(:page_title, gettext("Settings"))
  end

  @impl true
  def handle_event(
        "approve_lti_identity",
        %{"mapping_id" => mapping_id, "password" => password},
        socket
      ) do
    result =
      with {id, ""} <- Integer.parse(mapping_id) do
        Lti13.Users.authorize_legacy_user(socket.assigns.current_user, id, password)
      end

    case result do
      {:ok} ->
        {:noreply,
         socket
         |> put_flash(:info, gettext("LMS sign-in has been approved."))
         |> push_navigate(to: ~p"/users/settings")}

      {:error, %{reason: :rate_limited}} ->
        {:noreply,
         put_flash(
           socket,
           :error,
           gettext("Too many approval attempts. Please wait a minute and try again.")
         )}

      _ ->
        {:noreply,
         put_flash(
           socket,
           :error,
           gettext("Unable to approve LMS sign-in. Check your local password.")
         )}
    end
  end

  def handle_event("approve_lti_identity", _params, socket) do
    {:noreply,
     put_flash(
       socket,
       :error,
       gettext("Unable to approve LMS sign-in. Check your local password.")
     )}
  end

  @impl true
  def handle_event(
        "unlink",
        _params,
        socket
      )
      when length(socket.assigns.oidc_accounts) + length(socket.assigns.lti_accounts) == 1 and
             socket.assigns.current_user.is_randomized_password do
    {:noreply, socket |> redirect(to: ~p"/users/settings/set/password")}
  end

  @impl true
  def handle_event(
        "unlink",
        %{"issuer" => issuer} = _params,
        socket
      ) do
    Claper.Accounts.remove_oidc_user(socket.assigns.current_user, issuer)
    audit(socket, "user.identity_unlinked", %{provider: "oidc", issuer: issuer})

    {:noreply,
     socket
     |> put_flash(:info, gettext("The account has been unlinked."))
     |> push_navigate(to: ~p"/users/settings")}
  end

  @impl true
  def handle_event(
        "unlink",
        %{"registration_id" => registration_id} = _params,
        socket
      ) do
    Lti13.Users.remove_user(socket.assigns.current_user, registration_id)
    audit(socket, "user.identity_unlinked", %{provider: "lms", registration_id: registration_id})

    {:noreply,
     socket
     |> put_flash(:info, gettext("The account has been unlinked."))
     |> push_navigate(to: ~p"/users/settings")}
  end

  @impl true
  def handle_event("save", %{"action" => "update_profile", "user" => user_params}, socket) do
    case Accounts.update_user_profile(socket.assigns.current_user, user_params) do
      {:ok, user} ->
        audit(socket, "user.profile_updated")

        {:noreply,
         socket
         |> assign(:current_user, user)
         |> assign(:profile_changeset, Accounts.change_user_profile(user))
         |> put_flash(:info, gettext("Your profile has been updated."))
         |> push_navigate(to: ~p"/users/settings")}

      {:error, changeset} ->
        {:noreply, assign(socket, :profile_changeset, changeset)}
    end
  end

  @impl true
  # Two-step sign-in, switched on and off here (Jose, 2026-11-15): turning
  # it on goes to the setup page (an authenticator app has to scan a code);
  # turning it off needs a recent sign-in. Not when the administrators
  # require it for everyone.
  def handle_event("toggle_two_factor", _params, socket) do
    user = socket.assigns.current_user

    cond do
      Claper.Accounts.TwoFactor.required?(user) ->
        {:noreply,
         put_flash(socket, :error, gettext("Your administrator requires two-step sign-in."))}

      not Claper.Accounts.TwoFactor.enabled?(user) ->
        {:noreply, push_navigate(socket, to: ~p"/users/settings/two_factor?setup=1")}

      not ClaperWeb.UserAuth.recently_signed_in?(socket) ->
        {:noreply,
         redirect(socket, to: ClaperWeb.UserAuth.confirm_password_path(~p"/users/settings"))}

      true ->
        {:ok, user} = Claper.Accounts.TwoFactor.disable(user)
        audit(socket, "user.two_factor_disabled")
        Claper.Accounts.SecurityNotices.two_factor_off(user, :self)

        {:noreply,
         socket
         |> assign(:current_user, user)
         |> put_flash(:info, gettext("Two-step sign-in is off."))}
    end
  end

  def handle_event("save", %{"action" => "update_email"} = params, socket) do
    if ClaperWeb.UserAuth.recently_signed_in?(socket) do
      update_email(params, socket)
    else
      {:noreply,
       redirect(socket,
         to: ClaperWeb.UserAuth.confirm_password_path(~p"/users/settings/edit/email")
       )}
    end
  end

  def handle_event("save", %{"action" => "update_password"} = params, socket) do
    update_password(params, socket)
  end

  def handle_event("save", %{"action" => "update_preferences"} = params, socket) do
    update_preferences(params, socket)
  end

  def handle_event("save", %{"action" => "set_password"} = params, socket) do
    set_password(params, socket)
  end

  def handle_event("validate", _params, socket) do
    {:noreply, socket}
  end

  defp update_email(params, socket) do
    %{"user" => user_params} = params

    user = socket.assigns.current_user

    case Accounts.apply_user_email(user, user_params) do
      {:ok, applied_user} ->
        audit(socket, "user.email_change_requested", %{new_email: applied_user.email})

        Accounts.deliver_update_email_instructions(
          applied_user,
          user.email,
          &url(~p"/users/settings/confirm_email/#{&1}")
        )

        {:noreply,
         socket
         |> put_flash(
           :info,
           gettext("A link to confirm your email change has been sent to the new address.")
         )
         |> push_navigate(to: ~p"/users/settings")}

      {:error, changeset} ->
        {:noreply, assign(socket, :email_changeset, changeset)}
    end
  end

  defp update_password(params, socket) do
    %{"user" => user_params} = params
    %{"current_password" => password} = user_params

    user = socket.assigns.current_user

    case Accounts.update_user_password(user, password, user_params) do
      {:ok, _applied_user} ->
        audit(socket, "user.password_changed")
        Claper.Accounts.SecurityNotices.password_changed(user, :changed)

        {:noreply,
         socket
         |> put_flash(
           :info,
           gettext("Your password has been updated.")
         )
         |> push_navigate(to: ~p"/users/settings")}

      {:error, changeset} ->
        {:noreply, assign(socket, :password_changeset, changeset)}
    end
  end

  defp update_preferences(params, socket) do
    locale = params["user"]["locale"]
    available_locales = Gettext.known_locales(ClaperWeb.Gettext)

    if Enum.member?(available_locales, locale) do
      case Accounts.update_user_preferences(socket.assigns.current_user, params["user"]) do
        {:ok, _applied_user} ->
          {:noreply,
           socket
           |> put_flash(
             :info,
             gettext("Your preferences have been updated.")
           )
           |> redirect(to: ~p"/users/settings")}

        {:error, changeset} ->
          {:noreply, assign(socket, :preferences_changeset, changeset)}
      end
    else
      {:noreply, socket}
    end
  end

  defp set_password(params, socket) do
    %{"user" => user_params} = params

    user = socket.assigns.current_user

    case Accounts.set_user_password(user, user_params) do
      {:ok, _applied_user} ->
        audit(socket, "user.password_set")
        Claper.Accounts.SecurityNotices.password_changed(user, :set)

        {:noreply,
         socket
         |> put_flash(
           :info,
           gettext("Your password has been set, you can now unlink your account.")
         )
         |> redirect(to: ~p"/users/settings")}

      {:error, changeset} ->
        {:noreply, assign(socket, :password_changeset, changeset)}
    end
  end

  # Audit Log (docs/SECURITY.md)
  defp audit(socket, action, metadata \\ %{}) do
    Claper.Audit.record(socket.assigns.current_user, action,
      metadata: metadata,
      context: ClaperWeb.AuditContext.from_socket(socket)
    )
  end

  defp set_locale(user) when is_nil(user.locale) do
    %{"locale" => "en"}
  end

  defp set_locale(user) do
    %{"locale" => user.locale}
  end
end
