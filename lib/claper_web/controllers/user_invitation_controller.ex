defmodule ClaperWeb.UserInvitationController do
  @moduledoc """
  Accepting an administrator's invitation (docs/SECURITY.md): the person
  chooses their password (the usual rules) and is signed in. The link is
  checked when the form opens and again when it's saved, and works once.
  """
  use ClaperWeb, :controller

  alias Claper.Accounts
  alias Claper.Accounts.Administration
  alias ClaperWeb.UserAuth

  plug :get_invited_user

  def edit(conn, %{"token" => token}) do
    render(conn, "edit.html",
      changeset: Accounts.change_user_password(conn.assigns.invited_user),
      token: token
    )
  end

  def update(conn, %{"user" => params, "token" => token}) do
    user = conn.assigns.invited_user

    case Administration.accept_invitation(
           user,
           Map.take(params, ["password", "password_confirmation"])
         ) do
      {:ok, user} ->
        Claper.Audit.record(user, "user.invitation_accepted",
          context: ClaperWeb.AuditContext.from_conn(conn)
        )

        conn
        |> put_flash(:info, gettext("Welcome! Your password is set."))
        |> UserAuth.log_in_user(user, %{"auth_method" => "invitation"})

      {:error, changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> render("edit.html", changeset: changeset, token: token)
    end
  end

  defp get_invited_user(conn, _opts) do
    case Administration.get_invited_user(conn.params["token"]) do
      nil ->
        conn
        |> put_flash(
          :error,
          gettext(
            "This invitation link is invalid, already used or more than 7 days old. Ask an administrator to send a new one."
          )
        )
        |> redirect(to: ~p"/users/log_in")
        |> halt()

      user ->
        assign(conn, :invited_user, user)
    end
  end
end
