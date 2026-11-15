defmodule ClaperWeb.UserResetPasswordControllerTest do
  use ClaperWeb.ConnCase, async: false

  import Claper.AccountsFixtures

  alias Claper.Accounts.UserToken
  alias Claper.Repo

  describe "GET /users/reset_password" do
    test "renders the reset password request page", %{conn: conn} do
      conn = get(conn, ~p"/users/reset_password")
      response = html_response(conn, 200)

      assert response =~ "action=\"/users/reset_password\""
      assert response =~ "name=\"user[email]\""
      assert response =~ "/users/log_in"
    end
  end

  describe "POST /users/reset_password" do
    test "redirects with a neutral message for existing users", %{conn: conn} do
      user = user_fixture()

      conn =
        post(conn, ~p"/users/reset_password", %{
          "user" => %{"email" => user.email}
        })

      assert redirected_to(conn) == "/"

      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~
               "If your email is in our system"
    end

    test "redirects with the same neutral message for unknown users", %{conn: conn} do
      conn =
        post(conn, ~p"/users/reset_password", %{
          "user" => %{"email" => "unknown@example.com"}
        })

      assert redirected_to(conn) == "/"

      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~
               "If your email is in our system"
    end
  end

  describe "GET /users/reset_password/:token" do
    test "renders the password update page for a valid token", %{conn: conn} do
      user = user_fixture()

      {token, user_token} = UserToken.build_email_token(user, "reset_password")
      Repo.insert!(user_token)

      conn = get(conn, ~p"/users/reset_password/#{token}")
      response = html_response(conn, 200)

      assert response =~ "action=\"/users/reset_password/#{token}\""
      assert response =~ "name=\"user[password]\""
      assert response =~ "name=\"user[password_confirmation]\""
      assert response =~ ~s(autocomplete="new-password")
      assert response =~ ~s(value="#{user.email}" autocomplete="username")
      assert response =~ ~s(data-password-reveal)
    end
  end

  describe "POST /users/reset_password/:token" do
    setup do
      user = user_fixture()
      {token, user_token} = UserToken.build_email_token(user, "reset_password")
      Repo.insert!(user_token)
      %{user: user, token: token}
    end

    defp new_password(conn, token, password) do
      post(conn, ~p"/users/reset_password/#{token}", %{
        "user" => %{"password" => password, "password_confirmation" => password}
      })
    end

    test "sets the password, spends the link and ends every session", %{
      conn: conn,
      user: user,
      token: token
    } do
      session_token = Claper.Accounts.generate_user_session_token(user)
      conn = conn |> get(~p"/users/reset_password/#{token}") |> recycle()
      conn = new_password(conn, token, "a brand new sentence here")

      assert redirected_to(conn) == "/"

      assert Claper.Accounts.get_user_by_email_and_password(
               user.email,
               "a brand new sentence here"
             )

      assert Claper.Accounts.get_user_by_session_token(session_token) == nil

      again = conn |> recycle() |> new_password(token, "someone else's sentence")
      assert redirected_to(again) == "/"
      assert Phoenix.Flash.get(again.assigns.flash, :error) =~ "invalid or it has expired"
    end

    test "the same browser can't set a password again with a made-up link (the account comes from the link, not the session)",
         %{conn: conn, user: user, token: token} do
      conn = conn |> get(~p"/users/reset_password/#{token}") |> recycle()
      conn = conn |> new_password(token, "a brand new sentence here") |> recycle()

      conn = new_password(conn, "made-up-link", "an attacker's sentence!!")
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "invalid or it has expired"

      refute Claper.Accounts.get_user_by_email_and_password(
               user.email,
               "an attacker's sentence!!"
             )
    end

    test "an old session that still names an account can't use a made-up link", %{
      conn: conn,
      user: user
    } do
      conn = conn |> init_test_session(%{"user_id" => user.id})
      conn = new_password(conn, "made-up-link", "an attacker's sentence!!")
      assert redirected_to(conn) == "/"

      refute Claper.Accounts.get_user_by_email_and_password(
               user.email,
               "an attacker's sentence!!"
             )
    end

    test "a reset lifts the account's sign-in limit", %{conn: conn, user: user, token: token} do
      for _ <- 1..10, do: ClaperWeb.UserAuth.record_failed_attempt(user.email)
      assert {:error, :too_many_attempts} = ClaperWeb.UserAuth.check_account_attempts(user.email)

      new_password(conn, token, "a brand new sentence here")
      assert :ok = ClaperWeb.UserAuth.check_account_attempts(user.email)
    end
  end
end
