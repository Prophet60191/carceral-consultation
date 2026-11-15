defmodule ClaperWeb.UserTwoFactorController do
  @moduledoc """
  The second step of signing in, after a correct password, for accounts with
  two-step sign-in on (docs/SECURITY.md). Nothing is granted until a code
  checks out. The step closes after 5 minutes or 5 wrong codes, and codes
  count toward the account's sign-in attempts.
  """
  use ClaperWeb, :controller

  alias Claper.Accounts.TwoFactor
  alias ClaperWeb.UserAuth

  def new(conn, _params) do
    case UserAuth.pending_two_factor_user(conn) do
      {_user, _pending} -> render(conn, "new.html", error_message: nil)
      nil -> start_over(conn)
    end
  end

  def create(conn, %{"two_factor" => %{"code" => code}}) do
    with {user, pending} <- UserAuth.pending_two_factor_user(conn) do
      case UserAuth.check_account_attempts(user.email) do
        :ok -> check_code(conn, user, pending, code)
        {:error, :too_many_attempts} -> start_over(conn, UserAuth.too_many_attempts_message())
      end
    else
      nil -> start_over(conn)
    end
  end

  def create(conn, _params), do: new(conn, %{})

  defp check_code(conn, user, pending, code) do
    case TwoFactor.verify(user, code) do
      {:ok, user, method} ->
        conn
        |> UserAuth.clear_two_factor()
        |> maybe_warn_backup_codes(user, method)
        |> UserAuth.log_in_user(user, %{
          "remember_me" => if(pending["remember_me"], do: "true", else: "false"),
          "auth_method" =>
            if(method == :backup_code, do: "password+backup_code", else: "password+code")
        })

      :error ->
        UserAuth.record_failed_sign_in(conn, user, "wrong_code")

        conn
        |> UserAuth.count_wrong_code(pending)
        |> put_status(:unprocessable_entity)
        |> render("new.html",
          error_message: gettext("That code didn't work. Try the newest one.")
        )
    end
  end

  defp maybe_warn_backup_codes(conn, user, :backup_code) do
    put_flash(
      conn,
      :info,
      gettext(
        "You used a backup code; %{count} left. You can make new ones in My account.",
        count: TwoFactor.backup_codes_left(user)
      )
    )
  end

  defp maybe_warn_backup_codes(conn, _user, _method), do: conn

  defp start_over(conn, message \\ nil) do
    conn
    |> UserAuth.clear_two_factor()
    |> put_flash(:error, message || gettext("Please sign in again."))
    |> redirect(to: ~p"/users/log_in")
  end
end
