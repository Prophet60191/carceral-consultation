defmodule ClaperWeb.AdminLive.UserLive do
  use ClaperWeb, :admin_live_view

  import ClaperWeb.AdminLive.DetailComponents

  alias Claper.Admin
  alias Claper.Accounts
  alias Claper.Accounts.User
  alias Claper.Audit
  alias ClaperWeb.UserAuth
  alias Claper.Accounts.{Administration, TwoFactor}

  @impl true
  def mount(_params, session, socket) do
    with %{"locale" => locale} <- session do
      Gettext.put_locale(ClaperWeb.Gettext, locale)
    end

    {:ok, socket}
  end

  @impl true
  def handle_params(params, url, socket) do
    # Creating and editing accounts need a recent sign-in (docs/SECURITY.md)
    if socket.assigns.live_action in [:new, :edit] and not UserAuth.recently_signed_in?(socket) do
      {:noreply, redirect(socket, to: UserAuth.confirm_password_path(URI.parse(url).path))}
    else
      {:noreply, apply_action(socket, socket.assigns.live_action, params)}
    end
  end

  # Disabling, enabling and deleting accounts need a recent sign-in too
  defp with_recent_sign_in(socket, id, fun) do
    if UserAuth.recently_signed_in?(socket),
      do: fun.(),
      else:
        {:noreply, redirect(socket, to: UserAuth.confirm_password_path(~p"/admin/users/#{id}"))}
  end

  defp apply_action(socket, :index, params) do
    {users, meta} = Admin.list_users_paginated(params)

    socket
    |> assign(:page_title, gettext("Users"))
    |> assign(:user, nil)
    |> assign(:users, users)
    |> assign(:meta, meta)
    |> assign(:form, Phoenix.Component.to_form(meta))
    |> assign_new(:fields, fn ->
      [
        email: [
          label: nil,
          placeholder: gettext("Search users..."),
          type: "text",
          op: :ilike_or
        ]
      ]
    end)
  end

  defp apply_action(socket, :new, _params) do
    socket
    |> assign(:page_title, gettext("New user"))
    |> assign(:user, %User{})
  end

  defp apply_action(socket, :edit, %{"id" => id}) do
    socket
    |> assign(:page_title, gettext("Edit user"))
    |> assign(:user, Accounts.get_user!(id) |> Claper.Repo.preload(:role))
  end

  defp apply_action(socket, :show, %{"id" => id} = params) do
    user = Accounts.get_user!(id) |> Claper.Repo.preload(:role)

    # Both tables paginate on the same page: audit logs use the top-level
    # query params, events are namespaced under "events".
    {events_params, audit_params} = params |> Map.delete("id") |> Map.pop("events")
    events_params = if is_map(events_params), do: events_params, else: %{}

    {audit_logs, audit_meta} = Audit.list_logs_for_user(user, audit_params)
    {events, events_meta} = Admin.list_user_events_paginated(user.id, events_params)

    actor = socket.assigns.current_user

    socket
    |> assign(:page_title, gettext("User details"))
    |> assign(:user, user)
    |> assign(:two_factor_on, TwoFactor.enabled?(user))
    |> assign(:two_factor_required, TwoFactor.required?(user))
    |> assign(:invitation_pending, Administration.invitation_pending?(user))
    |> assign(:open_sessions, Administration.open_sessions(user))
    |> assign(:can_disable, Administration.check(actor, user, :disable) == :ok)
    |> assign(:can_delete, Administration.check(actor, user, :delete) == :ok)
    |> assign(:audit_logs, audit_logs)
    |> assign(:audit_meta, audit_meta)
    |> assign(:audit_path, ~p"/admin/users/#{user}?#{%{"events" => events_params}}")
    |> assign(:events, events)
    |> assign(:events_meta, events_meta)
    |> assign(:events_path, fn flop_params ->
      ~p"/admin/users/#{user}?#{Map.put(audit_params, "events", Map.new(flop_params))}"
    end)
  end

  @impl true
  def handle_info({ClaperWeb.AdminLive.UserLive.FormComponent, {:saved, _user}}, socket),
    do: {:noreply, socket}

  @impl true
  def handle_event("disable", %{"id" => id}, socket) do
    with_recent_sign_in(socket, id, fn -> disable_user(socket, id) end)
  end

  @impl true
  def handle_event("enable", %{"id" => id}, socket) do
    with_recent_sign_in(socket, id, fn -> enable_user(socket, id) end)
  end

  @impl true
  def handle_event("delete", %{"id" => id}, socket) do
    with_recent_sign_in(socket, id, fn -> delete_user(socket, id) end)
  end

  def handle_event(action, %{"id" => id}, socket)
      when action in [
             "resend_invitation",
             "send_reset",
             "sign_out_everywhere",
             "reset_two_factor"
           ] do
    with_recent_sign_in(socket, id, fn ->
      account_action(socket, action, Accounts.get_user!(id))
    end)
  end

  @impl true
  def handle_event("filter-users", unsigned_params, socket) do
    flop = Flop.validate!(unsigned_params, for: User, replace_invalid_params: true)
    to = Flop.Phoenix.build_path(~p"/admin/users", flop)

    {:noreply, push_patch(socket, to: to)}
  end

  defp disable_user(socket, id) do
    user = Accounts.get_user!(id)

    with :ok <- Administration.check(socket.assigns.current_user, user, :disable),
         {:ok, _user} <- Accounts.delete_user(user) do
      # Out at once, open pages included (docs/SECURITY.md)
      Administration.sign_out_everywhere(user)
      ClaperWeb.AuditContext.record(socket, "admin.user_disabled", target: user)

      {:noreply,
       socket
       |> put_flash(:info, gettext("User disabled. They've been signed out everywhere."))
       |> push_patch(to: ~p"/admin/users/#{user}")}
    else
      {:error, reason} when is_binary(reason) ->
        {:noreply, put_flash(socket, :error, reason)}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, gettext("Could not disable user"))}
    end
  end

  defp enable_user(socket, id) do
    user = Accounts.get_user!(id)

    case Accounts.restore_user(user) do
      {:ok, _user} ->
        ClaperWeb.AuditContext.record(socket, "admin.user_enabled", target: user)

        {:noreply,
         socket
         |> put_flash(:info, gettext("User enabled successfully"))
         |> push_patch(to: ~p"/admin/users/#{user}")}

      {:error, _changeset} ->
        {:noreply,
         put_flash(
           socket,
           :error,
           gettext("Could not enable user: another active account uses this email")
         )}
    end
  end

  defp delete_user(socket, id) do
    user = Accounts.get_user!(id)

    with :ok <- Administration.check(socket.assigns.current_user, user, :delete),
         :ok <- sign_out_before_delete(user),
         {:ok, _user} <- Accounts.hard_delete_user(user) do
      ClaperWeb.AuditContext.record(socket, "admin.user_deleted", target: user)

      {:noreply,
       socket
       |> put_flash(:info, gettext("User and all their data deleted permanently"))
       |> push_patch(to: ~p"/admin/users")}
    else
      {:error, reason} when is_binary(reason) -> {:noreply, put_flash(socket, :error, reason)}
      {:error, _reason} -> {:noreply, put_flash(socket, :error, gettext("Could not delete user"))}
    end
  end

  # Open pages are disconnected before the account goes
  defp sign_out_before_delete(user) do
    Administration.sign_out_everywhere(user)
    :ok
  end

  defp account_action(socket, "resend_invitation", user) do
    case Administration.resend_invitation(user, &url(~p"/users/invitation/#{&1}")) do
      {:ok, _} ->
        ClaperWeb.AuditContext.record(socket, "admin.invitation_resent", target: user)
        done(socket, user, gettext("Invitation sent again to %{email}.", email: user.email))

      {:error, :not_pending} ->
        {:noreply, put_flash(socket, :error, gettext("They've already accepted the invitation."))}
    end
  end

  defp account_action(socket, "send_reset", user) do
    Accounts.deliver_user_reset_password_instructions(user, &url(~p"/users/reset_password/#{&1}"))
    ClaperWeb.AuditContext.record(socket, "admin.password_reset_sent", target: user)
    done(socket, user, gettext("A password reset link went to %{email}.", email: user.email))
  end

  defp account_action(socket, "sign_out_everywhere", user) do
    {:ok, count} = Administration.sign_out_everywhere(user)

    ClaperWeb.AuditContext.record(socket, "admin.user_signed_out_everywhere",
      target: user,
      metadata: %{sessions: count}
    )

    message =
      if user.id == socket.assigns.current_user.id,
        do: gettext("All your sessions have ended."),
        else: ngettext("1 session ended.", "%{count} sessions ended.", count)

    done(socket, user, message)
  end

  defp account_action(socket, "reset_two_factor", user) do
    {:ok, _} = Administration.reset_two_factor(user)
    ClaperWeb.AuditContext.record(socket, "admin.two_factor_reset", target: user)

    done(
      socket,
      user,
      gettext(
        "Two-step sign-in is off for %{email}, and they've been signed out. If their role needs it, they'll set it up again when they sign in.",
        email: user.email
      )
    )
  end

  defp done(socket, user, message) do
    {:noreply, socket |> put_flash(:info, message) |> push_patch(to: ~p"/admin/users/#{user}")}
  end

  defp format_audit_metadata(nil), do: empty_value()
  defp format_audit_metadata(metadata) when map_size(metadata) == 0, do: empty_value()

  defp format_audit_metadata(metadata) do
    Enum.map_join(metadata, ", ", fn {k, v} -> "#{k}: #{v}" end)
  end

  # Invited, Active, Unconfirmed or Disabled
  attr :user, :any, required: true

  defp status_badge(assigns) do
    ~H"""
    <%= cond do %>
      <% @user.deleted_at -> %>
        <span class="badge badge-error">{gettext("Disabled")}</span>
      <% Administration.invitation_pending?(@user) -> %>
        <span class="badge badge-warning">{gettext("Invited")}</span>
      <% @user.confirmed_at -> %>
        <span class="badge badge-success">{gettext("Active")}</span>
      <% true -> %>
        <span class="badge badge-warning">{gettext("Unconfirmed")}</span>
    <% end %>
    """
  end

  # On, Off, or Needed (required but not set up yet)
  attr :user, :any, required: true

  defp two_factor_badge(assigns) do
    ~H"""
    <%= cond do %>
      <% TwoFactor.enabled?(@user) -> %>
        <span class="badge badge-success">{gettext("On")}</span>
      <% TwoFactor.required?(@user) -> %>
        <span class="badge badge-warning">{gettext("Needed")}</span>
      <% true -> %>
        <span class="badge">{gettext("Off")}</span>
    <% end %>
    """
  end
end
