defmodule ClaperWeb.UserAuth do
  @moduledoc """
    Plug for user authentication.
  """
  use ClaperWeb, :controller

  require Logger

  import Plug.Conn
  import Phoenix.Controller
  import ClaperWeb.Helpers.ConnUtils, only: [get_client_ip: 1, get_user_agent: 1]

  alias Claper.{Accounts, Audit}
  alias Claper.Accounts.{KnownDevices, TwoFactor}

  # Make the remember me cookie valid for 60 days.
  # If you want bump or reduce this value, also change
  # the token expiry itself in UserToken.
  @max_age 60 * 60 * 24 * 60
  @remember_me_cookie "_claper_web_user_remember_me"
  @remember_me_options [sign: true, max_age: @max_age, same_site: "Lax", http_only: true]

  # HTTPS-only when the session cookie is (served over https, docs/SECURITY.md)
  defp remember_me_options do
    secure = Application.get_env(:claper, ClaperWeb.Endpoint)[:secure_cookie] == true
    Keyword.put(@remember_me_options, :secure, secure)
  end

  @doc """
  Logs the user in.

  It renews the session ID and clears the whole session
  to avoid fixation attacks. See the renew_session
  function to customize this behaviour.

  It also sets a `:live_socket_id` key in the session,
  so LiveView sessions are identified and automatically
  disconnected on log out. The line can be safely removed
  if you are not using LiveView.
  """
  def log_in_user(conn, user, params \\ %{}) do
    clear_account_attempts(user.email)
    Claper.Accounts.Administration.touch_last_sign_in(user)
    # The browser and address, for My account › Sessions
    token = Accounts.generate_user_session_token(user, ClaperWeb.AuditContext.from_conn(conn))
    user_return_to = get_session(conn, :user_return_to)

    # How they got in: password, password + code, outside provider, ...
    async_log_action(user, "user.login", %{
      ip_address: get_client_ip(conn),
      user_agent: get_user_agent(conn),
      method: params["auth_method"] || "password"
    })

    conn
    |> renew_session()
    |> track_device(user, params["auth_method"] || "password")
    |> put_session(:user_token, token)
    |> put_session(:live_socket_id, "users_sessions:#{Base.url_encode64(token)}")
    |> maybe_write_remember_me_cookie(token, params)
    |> redirect(to: user_return_to || signed_in_path(conn))
  end

  ## Two-step sign-in (docs/SECURITY.md)

  # How long the code step waits after the password, and how many wrong codes
  # it takes before starting over
  @code_step_seconds 5 * 60
  @code_step_attempts 5

  @doc """
  After a correct password: signs in, or, with two-step sign-in on, keeps
  the person half-way (nothing is granted yet) and asks for a code.
  """
  def log_in_or_ask_for_code(conn, user, params \\ %{}) do
    if TwoFactor.enabled?(user) do
      conn
      |> put_session(:two_factor, %{
        "user_id" => user.id,
        "started_at" => System.system_time(:second),
        "attempts" => 0,
        "remember_me" => params["remember_me"] == "true"
      })
      |> redirect(to: ~p"/users/two_factor")
    else
      log_in_user(conn, user, params)
    end
  end

  @doc "The person half-way through signing in, if the code step is still open."
  def pending_two_factor_user(conn) do
    with %{"user_id" => id, "started_at" => started} = pending <- get_session(conn, :two_factor),
         true <- System.system_time(:second) - started <= @code_step_seconds,
         true <- pending["attempts"] < @code_step_attempts,
         %Accounts.User{} = user <- Accounts.get_user(id),
         true <- TwoFactor.enabled?(user) do
      {user, pending}
    else
      _ -> nil
    end
  end

  @doc "A wrong code: counted, and the step closes after too many."
  def count_wrong_code(conn, pending) do
    put_session(conn, :two_factor, Map.update!(pending, "attempts", &(&1 + 1)))
  end

  def clear_two_factor(conn), do: delete_session(conn, :two_factor)

  ## Attempts per account

  @account_attempts 10
  @account_window_ms :timer.minutes(15)

  @doc """
  At most #{@account_attempts} failed sign-in tries per account in any 15
  minutes (a sliding window), wherever they come from: passwords and codes
  alike. The same answer whether or not the account exists. Only failures
  count (`record_failed_attempt/1`), a successful sign-in clears them
  (`clear_account_attempts/1`, as NIST SP 800-63B-4 asks), and so does a
  password reset.
  """
  def check_account_attempts(email) when is_binary(email) do
    if Claper.AuthRateLimit.blocked?(account_key(email), @account_window_ms, @account_attempts),
      do: {:error, :too_many_attempts},
      else: :ok
  end

  def check_account_attempts(_), do: :ok

  def record_failed_attempt(email) when is_binary(email),
    do: Claper.AuthRateLimit.record_failure(account_key(email), @account_window_ms)

  def record_failed_attempt(_), do: :ok

  @doc """
  A wrong password or code: counted toward the account's limit and, when
  the account exists, written to the Audit Log on that account
  ("user.login_failed", and "user.login_paused" when it reaches the limit).
  Tries against addresses with no account are only counted: what people type
  there is sometimes a password typed in the wrong box.
  """
  def record_failed_sign_in(conn, %Accounts.User{} = user, reason) do
    record_failed_attempt(user.email)
    context = ClaperWeb.AuditContext.from_conn(conn)

    Audit.record(user, "user.login_failed", metadata: %{reason: reason}, context: context)

    if Claper.AuthRateLimit.count(account_key(user.email), @account_window_ms) ==
         @account_attempts do
      Audit.record(user, "user.login_paused",
        metadata: %{attempts: @account_attempts, window_minutes: 15},
        context: context
      )
    end

    :ok
  end

  def record_failed_sign_in(conn, email, reason) when is_binary(email) do
    case Accounts.get_user_by_email(String.trim(email)) do
      %Accounts.User{} = user -> record_failed_sign_in(conn, user, reason)
      nil -> record_failed_attempt(email)
    end
  end

  def record_failed_sign_in(_conn, _email, _reason), do: :ok

  def clear_account_attempts(email) when is_binary(email),
    do: Claper.AuthRateLimit.clear(account_key(email))

  def clear_account_attempts(_), do: :ok

  defp account_key(email), do: "login-account:" <> (email |> String.trim() |> String.downcase())

  def too_many_attempts_message do
    gettext(
      "Too many sign-in attempts for this account. Wait 15 minutes, or reset your password."
    )
  end

  ## Recent sign-in for sensitive actions ("sudo mode")

  @recent_minutes 15

  @doc """
  Did this session sign in (or confirm its password) within the last
  #{@recent_minutes} minutes? Asked before changing an email address,
  deleting an account, turning off two-step sign-in, and administrators'
  changes to accounts.
  """
  def recently_signed_in?(%Plug.Conn{} = conn),
    do: recent?(Accounts.session_signed_in_at(get_session(conn, :user_token)))

  def recently_signed_in?(%Phoenix.LiveView.Socket{} = socket),
    do: recent?(socket.assigns[:signed_in_at])

  def recently_signed_in?(signed_in_at), do: recent?(signed_in_at)

  defp recent?(%NaiveDateTime{} = at),
    do: NaiveDateTime.diff(NaiveDateTime.utc_now(), at, :second) <= @recent_minutes * 60

  defp recent?(_), do: false

  @doc "Where to confirm the password, coming back to `return_to` afterwards."
  def confirm_password_path(return_to),
    do: ~p"/users/confirm_password?#{[return_to: safe_return_to(return_to)]}"

  @doc "Only paths inside the app: never another site."
  def safe_return_to("/" <> rest = path) do
    if String.starts_with?(rest, ["/", "\\"]), do: "/users/settings", else: path
  end

  def safe_return_to(_), do: "/users/settings"

  ## New-device email (docs/SECURITY.md)

  @device_cookie "_cc_device"
  # The longest browsers keep a cookie (Chrome: 400 days)
  @device_max_age 60 * 60 * 24 * 400

  # Every browser keeps a random ID; an account signing in from one it has
  # never used gets the owner an email. A brand-new account's first browser,
  # and the first one recorded for an older account, are quiet.
  defp track_device(conn, user, method) do
    conn = fetch_cookies(conn, signed: [@device_cookie])

    {device_id, conn} =
      case conn.cookies[@device_cookie] do
        id when is_binary(id) ->
          {id, conn}

        _ ->
          id = :crypto.strong_rand_bytes(18) |> Base.url_encode64(padding: false)
          {id, put_resp_cookie(conn, @device_cookie, id, device_cookie_options())}
      end

    context = ClaperWeb.AuditContext.from_conn(conn)

    if KnownDevices.seen(user, device_id, context) == :new and method != "sign_up" do
      notify_new_device(user, context)
    end

    conn
  end

  defp device_cookie_options do
    secure = Application.get_env(:claper, ClaperWeb.Endpoint)[:secure_cookie] == true
    [sign: true, max_age: @device_max_age, same_site: "Lax", http_only: true, secure: secure]
  end

  defp notify_new_device(user, context) do
    browser = ClaperWeb.UserAgent.describe(context[:user_agent])

    Audit.record(user, "user.new_device", metadata: %{browser: browser}, context: context)

    Claper.Workers.Mailers.new_device(
      user.id,
      browser,
      context[:ip_address],
      DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601(),
      user.locale || Gettext.get_locale(ClaperWeb.Gettext)
    )
    |> Oban.insert()
  end

  defp maybe_write_remember_me_cookie(conn, token, %{"remember_me" => "true"}) do
    put_resp_cookie(conn, @remember_me_cookie, token, remember_me_options())
  end

  defp maybe_write_remember_me_cookie(conn, _token, _params) do
    conn
  end

  # This function renews the session ID and erases the whole
  # session to avoid fixation attacks. If there is any data
  # in the session you may want to preserve after log in/log out,
  # you must explicitly fetch the session data before clearing
  # and then immediately set it after clearing, for example:
  #
  #     defp renew_session(conn) do
  #       preferred_locale = get_session(conn, :preferred_locale)
  #
  #       conn
  #       |> configure_session(renew: true)
  #       |> clear_session()
  #       |> put_session(:preferred_locale, preferred_locale)
  #     end
  #
  defp renew_session(conn) do
    conn
    |> configure_session(renew: true)
    |> clear_session()
  end

  @doc """
  Logs the user out.

  It clears all session data for safety. See renew_session.
  """
  def log_out_user(conn) do
    logout_redirect_url = Application.get_env(:claper, :logout_redirect_url)
    user_token = get_session(conn, :user_token)
    user_token && Accounts.delete_session_token(user_token)

    if live_socket_id = get_session(conn, :live_socket_id) do
      ClaperWeb.Endpoint.broadcast(live_socket_id, "disconnect", %{})
    end

    async_log_action(conn.assigns[:current_user], "user.logout", %{
      ip_address: get_client_ip(conn),
      user_agent: get_user_agent(conn)
    })

    conn
    |> renew_session()
    |> delete_resp_cookie(@remember_me_cookie)
    |> custom_logout_redirect(logout_redirect_url)
  end

  defp custom_logout_redirect(conn, nil), do: conn |> redirect(to: "/")

  defp custom_logout_redirect(conn, logout_redirect_url),
    do: conn |> redirect(external: logout_redirect_url)

  @doc """
  Authenticates the user by looking into the session
  and remember me token.
  """
  def fetch_current_user(conn, _opts) do
    {user_token, conn} = ensure_user_token(conn)
    user = user_token && Accounts.get_user_by_session_token(user_token)

    # Sessions issued before the token-only cookie still carry the user struct.
    conn
    |> delete_session(:current_user)
    |> assign(:current_user, user)
  end

  @doc """
  Assigns the user owning the session token to a LiveView socket.

  Only the token lives in the session cookie; the user is loaded from the
  database so revoked tokens and account changes apply on the next mount.
  The dead render reuses the user already loaded by `fetch_current_user/2`.
  """
  def mount_current_user(socket, session) do
    socket
    |> Phoenix.Component.assign_new(:current_user, fn ->
      if user_token = session["user_token"] do
        Accounts.get_user_by_session_token(user_token)
      end
    end)
    # When this session signed in, for actions that need a recent sign-in
    |> Phoenix.Component.assign_new(:signed_in_at, fn ->
      Accounts.session_signed_in_at(session["user_token"])
    end)
  end

  defp ensure_user_token(conn) do
    if user_token = get_session(conn, :user_token) do
      {user_token, conn}
    else
      conn = fetch_cookies(conn, signed: [@remember_me_cookie])

      if user_token = conn.cookies[@remember_me_cookie] do
        {user_token, put_session(conn, :user_token, user_token)}
      else
        {nil, conn}
      end
    end
  end

  @doc """
  Used for routes that require the user to not be authenticated.
  """
  def redirect_if_user_is_authenticated(conn, _opts) do
    if conn.assigns[:current_user] do
      conn
      |> redirect(to: signed_in_path(conn))
      |> halt()
    else
      conn
    end
  end

  @doc """
  Used for routes that require the user to be authenticated.

  If you want to enforce the user email is confirmed before
  they use the application at all, here would be a good place.
  """
  def require_authenticated_user(conn, _opts) do
    if user = conn.assigns[:current_user] do
      require_two_factor_setup(conn, user)
    else
      conn
      |> put_flash(:error, gettext("You must log in to access this page."))
      |> maybe_store_return_to()
      |> redirect(to: ~p"/users/log_in")
      |> halt()
    end
  end

  # Someone who must use two-step sign-in and hasn't set it up goes to the
  # setup page first (LiveViews: ClaperWeb.TwoFactorHook).
  @setup_paths ["/users/settings/two_factor", "/users/log_out", "/users/confirm_password"]

  defp require_two_factor_setup(conn, user) do
    if conn.request_path not in @setup_paths and TwoFactor.setup_needed?(user) do
      conn
      |> put_flash(:info, two_factor_setup_message())
      |> redirect(to: ~p"/users/settings/two_factor")
      |> halt()
    else
      conn
    end
  end

  def two_factor_setup_message do
    gettext(
      "Your administrator requires two-step sign-in. Turn it on to continue: it takes a minute, with an app on your phone."
    )
  end

  defp maybe_store_return_to(%{method: "GET"} = conn) do
    put_session(conn, :user_return_to, current_path(conn))
  end

  defp maybe_store_return_to(conn), do: conn

  defp signed_in_path(_conn), do: "/events"

  defp async_log_action(user, action, metadata) do
    Task.Supervisor.start_child(Claper.TaskSupervisor, fn ->
      with {:error, reason} <- Audit.log_action(user, action, metadata) do
        Logger.error(
          "Error creating #{inspect(action)} audit log for user #{inspect(get_in(user.email))}: #{inspect(reason)}"
        )
      end
    end)
  end
end
