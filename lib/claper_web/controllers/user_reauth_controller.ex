defmodule ClaperWeb.UserReauthController do
  @moduledoc """
  "Confirm it's you" before a sensitive action, when this session signed in
  more than 15 minutes ago (docs/SECURITY.md, "sudo mode"): changing the
  email address, deleting the account, turning off two-step sign-in, and
  administrators' changes to accounts. Someone using a computer left signed
  in can't do those without the password (and the code, if two-step sign-in
  is on).

  Confirming starts a fresh session (the old one ends) and goes back to
  where the person was.
  """
  use ClaperWeb, :controller

  alias Claper.Accounts
  alias Claper.Accounts.TwoFactor
  alias ClaperWeb.UserAuth

  def new(conn, params) do
    render_form(conn, params["return_to"], nil)
  end

  def create(conn, %{"reauth" => reauth}) do
    user = conn.assigns.current_user
    return_to = UserAuth.safe_return_to(reauth["return_to"])

    with :ok <- UserAuth.check_account_attempts(user.email),
         %Accounts.User{} <-
           Accounts.get_user_by_email_and_password(user.email, reauth["password"] || ""),
         :ok <- check_code(user, reauth["code"]) do
      old_token = get_session(conn, :user_token)
      old_token && Accounts.delete_session_token(old_token)

      conn
      |> put_session(:user_return_to, return_to)
      |> UserAuth.log_in_user(user, %{
        "remember_me" => remember_me(conn),
        "auth_method" => "confirm_password"
      })
    else
      {:error, :too_many_attempts} ->
        render_form(conn, return_to, UserAuth.too_many_attempts_message())

      _ ->
        UserAuth.record_failed_sign_in(conn, user, "confirm_password_failed")

        render_form(
          conn,
          return_to,
          if(TwoFactor.enabled?(user),
            do: gettext("That password or code didn't work."),
            else: gettext("That password didn't work.")
          )
        )
    end
  end

  def create(conn, params), do: new(conn, params)

  defp check_code(user, code) do
    cond do
      not TwoFactor.enabled?(user) -> :ok
      match?({:ok, _, _}, TwoFactor.verify(user, code || "")) -> :ok
      true -> :error
    end
  end

  # Keep "remember me" if this browser had it
  defp remember_me(conn) do
    conn = fetch_cookies(conn, signed: ["_claper_web_user_remember_me"])
    if conn.cookies["_claper_web_user_remember_me"], do: "true", else: "false"
  end

  defp render_form(conn, return_to, error_message) do
    conn
    |> put_status(if error_message, do: :unprocessable_entity, else: :ok)
    |> render("new.html",
      return_to: UserAuth.safe_return_to(return_to),
      two_factor: TwoFactor.enabled?(conn.assigns.current_user),
      error_message: error_message
    )
  end
end
