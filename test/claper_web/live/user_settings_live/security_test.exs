defmodule ClaperWeb.UserSettingsLive.SecurityTest do
  @moduledoc """
  My account › Sessions and activity, and security notices
  (docs/SECURITY.md).
  """
  use ClaperWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Claper.AccountsFixtures
  import Swoosh.TestAssertions

  alias Claper.Accounts
  alias Claper.Accounts.{Sessions, TwoFactor}

  @iphone "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1"

  # Emails go to the test (config/runtime.exs picks the app's own mailer)
  setup do
    mailer = Application.get_env(:claper, Claper.Mailer)
    Application.put_env(:claper, Claper.Mailer, adapter: Swoosh.Adapters.Test)
    on_exit(fn -> Application.put_env(:claper, Claper.Mailer, mailer) end)

    for name <- ["user", "admin"] do
      _ = Accounts.get_role_by_name(name) || elem(Accounts.create_role(%{name: name}), 1)
    end

    :ok
  end

  defp other_session(user),
    do:
      Accounts.generate_user_session_token(user, %{user_agent: @iphone, ip_address: "203.0.113.7"})

  describe "where you're signed in" do
    test "lists sessions with browser and address, marks this one, and signs others out", %{
      conn: conn
    } do
      user = user_fixture()
      conn = log_in_user(conn, user)
      other = other_session(user)

      {:ok, view, html} = live(conn, ~p"/users/settings/security")
      assert html =~ "This browser"
      assert html =~ "Safari on iPhone"
      assert html =~ "203.0.113.7"

      [%{id: other_id}] =
        user |> Sessions.list(get_session(conn, :user_token)) |> Enum.reject(& &1.current)

      view |> element("#session-#{other_id} button") |> render_click()

      assert Accounts.get_user_by_session_token(other) == nil
      assert Accounts.get_user_by_session_token(get_session(conn, :user_token))
    end

    test "sign out everywhere else keeps this browser", %{conn: conn} do
      user = user_fixture()
      conn = log_in_user(conn, user)
      others = [other_session(user), other_session(user)]

      {:ok, view, _} = live(conn, ~p"/users/settings/security")
      view |> element("#sign-out-others") |> render_click()

      for t <- others, do: assert(Accounts.get_user_by_session_token(t) == nil)
      assert Accounts.get_user_by_session_token(get_session(conn, :user_token))
    end

    test "nobody can sign out someone else's session" do
      [me, them] = [user_fixture(), user_fixture()]
      their_token = other_session(them)
      [%{id: their_id}] = Sessions.list(them, nil)

      assert :error = Sessions.sign_out(me, their_id, nil)
      assert Accounts.get_user_by_session_token(their_token)
    end
  end

  describe "recent activity" do
    test "shows your own sign-ins and changes, and what administrators did to your account", %{
      conn: conn
    } do
      user = user_fixture()
      someone = user_fixture()
      {:ok, admin} = Accounts.assign_role(user_fixture(), "admin")

      Claper.Audit.record(user, "user.login",
        metadata: %{method: "password+code"},
        context: %{ip_address: "198.51.100.4", user_agent: @iphone}
      )

      Claper.Audit.record(user, "user.login_failed", metadata: %{reason: "wrong_password"})

      Claper.Audit.record(admin, "admin.user_role_changed",
        target: user,
        metadata: %{from: "user", to: "admin"}
      )

      Claper.Audit.record(someone, "user.password_changed")

      {:ok, _view, html} = live(log_in_user(conn, user), ~p"/users/settings/security")
      assert html =~ "You signed in with your password and a code"
      assert html =~ "Safari on iPhone · 198.51.100.4"
      assert html =~ "A sign-in failed: wrong password"
      assert html =~ "An administrator changed your role from Facilitator to Administrator"
      refute html =~ "You changed your password"
    end
  end

  describe "security notices" do
    test "changing your password tells you by email", %{conn: conn} do
      user = user_fixture()
      {:ok, view, _} = live(log_in_user(conn, user), ~p"/users/settings/edit/password")

      view
      |> form("#update_password", %{
        "user" => %{
          "current_password" => valid_user_password(),
          "password" => "a whole new sentence now"
        }
      })
      |> render_submit()

      assert_email_sent(fn email ->
        assert email.to == [{"", user.email}]
        assert email.subject =~ "password was changed"
      end)
    end

    test "a changed email address is reported to the old address", %{conn: conn} do
      user = user_fixture()
      old_email = user.email
      {:ok, applied} = Accounts.apply_user_email(user, %{"email" => "new-me@example.org"})

      Accounts.deliver_update_email_instructions(applied, old_email, fn token ->
        send(self(), {:token, token})
        "url"
      end)

      assert_received {:token, token}
      # The link to the new address comes first
      assert_email_sent(subject: "Update email instructions")
      conn |> log_in_user(user) |> get(~p"/users/settings/confirm_email/#{token}")

      assert_email_sent(fn email ->
        email.to == [{"", old_email}] and email.html_body =~ "new-me@example.org"
      end)
    end

    test "two-step sign-in turned off by an administrator is reported" do
      {user, _secret, _} = enable_two_factor(user_fixture())
      {:ok, _} = Claper.Accounts.Administration.reset_two_factor(user)
      refute TwoFactor.enabled?(Accounts.get_user!(user.id))

      assert_email_sent(fn email ->
        assert email.to == [{"", user.email}]
        assert email.subject =~ "Two-step sign-in was turned off"
        assert email.html_body =~ "An administrator turned off"
      end)
    end
  end
end
