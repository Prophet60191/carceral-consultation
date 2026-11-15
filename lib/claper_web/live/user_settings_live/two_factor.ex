defmodule ClaperWeb.UserSettingsLive.TwoFactor do
  @moduledoc """
  My account › Two-step sign-in (docs/SECURITY.md): turn it on with an
  authenticator app, see how many backup codes are left, make new ones, or
  turn it off (not allowed where it's required).

  Turning it on or off and making new codes need a recent sign-in
  (`ClaperWeb.UserAuth.recently_signed_in?/1`): otherwise someone at a
  computer left signed in could attach their own phone and lock the owner
  out.
  """
  use ClaperWeb, :live_view

  alias Claper.Accounts.TwoFactor
  alias ClaperWeb.UserAuth

  on_mount(ClaperWeb.UserLiveAuth)
  on_mount(ClaperWeb.ReturnContextHook)

  @path "/users/settings/two_factor"

  @impl true
  def mount(_params, session, socket) do
    with %{"locale" => locale} <- session do
      Gettext.put_locale(ClaperWeb.Gettext, locale)
    end

    {:ok,
     socket
     |> assign(:page_title, gettext("Two-step sign-in"))
     |> assign(:setup, nil)
     |> assign(:codes, nil)
     |> assign(:error, nil)
     |> assign_status()}
  end

  # From the switch in My account: go straight into setting it up
  @impl true
  def handle_params(%{"setup" => "1"}, _url, socket) do
    if socket.assigns.enabled or socket.assigns.setup do
      {:noreply, socket}
    else
      {:noreply, elem(handle_event("start", %{}, socket), 1)}
    end
  end

  def handle_params(_params, _url, socket), do: {:noreply, socket}

  defp assign_status(socket) do
    user = socket.assigns.current_user

    socket
    |> assign(:enabled, TwoFactor.enabled?(user))
    |> assign(:required, TwoFactor.required?(user))
    |> assign(:codes_left, TwoFactor.backup_codes_left(user))
  end

  @impl true
  def handle_event("start", _params, socket) do
    with_recent_sign_in(socket, fn ->
      secret = TwoFactor.new_secret()
      user = socket.assigns.current_user

      {:noreply,
       assign(socket,
         setup: %{
           secret: secret,
           uri: TwoFactor.otpauth_uri(user, secret),
           text: TwoFactor.secret_text(secret)
         },
         error: nil
       )}
    end)
  end

  def handle_event("cancel", _params, socket) do
    {:noreply, assign(socket, setup: nil, error: nil)}
  end

  def handle_event("confirm", %{"code" => code}, socket) do
    with %{secret: secret} <- socket.assigns.setup,
         {:ok, user, codes} <-
           TwoFactor.enable(socket.assigns.current_user, secret, String.replace(code, ~r/\s/, "")) do
      audit(socket, "user.two_factor_enabled")

      {:noreply,
       socket
       |> assign(current_user: user, setup: nil, codes: codes, error: nil)
       |> assign_status()}
    else
      _ ->
        {:noreply,
         assign(socket,
           error:
             gettext(
               "That code didn't work. Check the time on your phone, then try the newest code."
             )
         )}
    end
  end

  def handle_event("new_codes", _params, socket) do
    with_recent_sign_in(socket, fn ->
      {:ok, user, codes} = TwoFactor.regenerate_backup_codes(socket.assigns.current_user)
      audit(socket, "user.backup_codes_regenerated")
      {:noreply, socket |> assign(current_user: user, codes: codes) |> assign_status()}
    end)
  end

  def handle_event("done", _params, socket) do
    {:noreply, assign(socket, :codes, nil)}
  end

  def handle_event("disable", _params, socket) do
    if socket.assigns.required do
      {:noreply,
       put_flash(socket, :error, gettext("Your administrator requires two-step sign-in."))}
    else
      with_recent_sign_in(socket, fn ->
        {:ok, user} = TwoFactor.disable(socket.assigns.current_user)
        audit(socket, "user.two_factor_disabled")
        Claper.Accounts.SecurityNotices.two_factor_off(user, :self)

        {:noreply,
         socket
         |> assign(current_user: user, codes: nil)
         |> assign_status()
         |> put_flash(:info, gettext("Two-step sign-in is off."))}
      end)
    end
  end

  defp audit(socket, action) do
    Claper.Audit.record(socket.assigns.current_user, action,
      context: ClaperWeb.AuditContext.from_socket(socket)
    )
  end

  defp with_recent_sign_in(socket, fun) do
    if UserAuth.recently_signed_in?(socket),
      do: fun.(),
      else: {:noreply, redirect(socket, to: UserAuth.confirm_password_path(@path <> "?setup=1"))}
  end
end
