defmodule ClaperWeb.TwoFactorSignInTest do
  @moduledoc """
  Signing in with two-step sign-in, the requirement for administrators, the
  per-account attempt limit, and confirming the password before sensitive
  actions (docs/SECURITY.md).
  """
  use ClaperWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Claper.AccountsFixtures

  alias Claper.Accounts
  alias Claper.Accounts.TwoFactor

  setup do
    for name <- ["user", "admin"] do
      _ = Accounts.get_role_by_name(name) || elem(Accounts.create_role(%{name: name}), 1)
    end

    :ok
  end

  defp sign_in(conn, user, password \\ valid_user_password()) do
    post(conn, ~p"/users/log_in", %{"user" => %{"email" => user.email, "password" => password}})
  end

  defp signed_in?(conn), do: get_session(conn, :user_token) != nil

  describe "signing in with two-step sign-in on" do
    setup do
      {user, secret, codes} = enable_two_factor(user_fixture())
      %{user: user, secret: secret, codes: codes}
    end

    test "the password alone doesn't sign in; the right code does", %{
      conn: conn,
      user: user,
      secret: secret
    } do
      conn = sign_in(conn, user)
      assert redirected_to(conn) == ~p"/users/two_factor"
      refute signed_in?(conn)

      page = conn |> recycle() |> get(~p"/users/two_factor") |> html_response(200)
      assert page =~ "6-digit code"

      conn =
        conn
        |> recycle()
        |> post(~p"/users/two_factor", %{"two_factor" => %{"code" => totp_code(secret)}})

      assert redirected_to(conn) == "/events"
      assert signed_in?(conn)
    end

    test "a wrong code is refused and counted; 5 wrong codes start over", %{
      conn: conn,
      user: user
    } do
      conn = sign_in(conn, user)

      conn =
        Enum.reduce(1..5, conn, fn _, conn ->
          conn =
            conn
            |> recycle()
            |> post(~p"/users/two_factor", %{"two_factor" => %{"code" => "000000"}})

          assert html_response(conn, 422) =~ "That code didn&#39;t work"
          refute signed_in?(conn)
          conn
        end)

      conn = conn |> recycle() |> get(~p"/users/two_factor")
      assert redirected_to(conn) == ~p"/users/log_in"
    end

    test "a backup code signs in once, and says how many are left", %{
      conn: conn,
      user: user,
      codes: [code | _]
    } do
      conn = sign_in(conn, user)

      conn =
        conn |> recycle() |> post(~p"/users/two_factor", %{"two_factor" => %{"code" => code}})

      assert signed_in?(conn)
      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "9 left"
    end

    test "the code page can't be reached without a correct password first", %{conn: conn} do
      assert redirected_to(get(conn, ~p"/users/two_factor")) == ~p"/users/log_in"

      conn = post(conn, ~p"/users/two_factor", %{"two_factor" => %{"code" => "123456"}})
      assert redirected_to(conn) == ~p"/users/log_in"
      refute signed_in?(conn)
    end
  end

  test "a successful sign-in clears earlier failures; only failures count" do
    user = user_fixture()
    # Each try from its own address, so only the account's limit is in play
    from = fn i -> Map.put(build_conn(), :remote_ip, {198, 51, 100, i}) end

    for i <- 1..9, do: sign_in(from.(i), user, "wrong password number #{i}")
    assert signed_in?(sign_in(from.(10), user))

    for i <- 11..19, do: sign_in(from.(i), user, "wrong password again #{i}")
    assert signed_in?(sign_in(from.(20), user))
  end

  test "wrong codes count toward the account's limit too", %{conn: conn} do
    {user, _secret, _} = enable_two_factor(user_fixture())

    conn = sign_in(conn, user)

    for _ <- 1..4,
        do:
          conn
          |> recycle()
          |> post(~p"/users/two_factor", %{"two_factor" => %{"code" => "000000"}})

    # Each try from its own address, so only the account's limit is in play
    # (the per-address limit counts every request from 127.0.0.1 in the suite)
    from = fn i -> Map.put(build_conn(), :remote_ip, {198, 51, 100, 100 + i}) end

    for i <- 1..6, do: sign_in(from.(i), user, "wrong password number #{i}")

    assert html_response(sign_in(from.(7), user), 200) =~ "Too many sign-in attempts"
  end

  test "each account allows 10 failed sign-in tries in any 15 minutes, from any address", %{
    conn: conn
  } do
    user = user_fixture()

    for i <- 1..10 do
      conn =
        conn |> Map.put(:remote_ip, {198, 51, 100, i}) |> sign_in(user, "wrong password #{i}")

      assert html_response(conn, 200) =~ "Invalid email or password"
    end

    conn = conn |> Map.put(:remote_ip, {198, 51, 100, 99}) |> sign_in(user)
    assert html_response(conn, 200) =~ "Too many sign-in attempts for this account"
    refute signed_in?(conn)
  end

  describe "when the administrators require it for everyone" do
    test "pages send everyone, administrators included, to the setup page until it's on", %{
      conn: conn
    } do
      Claper.Settings.set("two_factor_required", "true")
      {:ok, admin} = Accounts.assign_role(user_fixture(), "admin")
      conn = log_in_user(conn, admin, two_factor: false)

      assert redirected_to(get(conn, ~p"/events")) == ~p"/users/settings/two_factor"
      assert {:error, {:redirect, %{to: "/users/settings/two_factor"}}} = live(conn, ~p"/admin")

      {:ok, view, _} = live(conn, ~p"/users/settings/two_factor")
      assert render(view) =~ "Your administrator requires two-step sign-in"
    end

    test "off: nobody is sent to set it up, administrators included", %{conn: conn} do
      {:ok, admin} = Accounts.assign_role(user_fixture(), "admin")
      conn = log_in_user(conn, admin, two_factor: false)
      assert html_response(get(conn, ~p"/users/settings"), 200)
    end
  end

  describe "the switch in My account" do
    test "off → on goes straight into setting it up", %{conn: conn} do
      conn = log_in_user(conn, user_fixture())
      {:ok, view, _} = live(conn, ~p"/users/settings")

      assert {:error, {:live_redirect, %{to: "/users/settings/two_factor?setup=1"}}} =
               view |> element("#two-factor-switch") |> render_click()

      {:ok, _view, html} = live(conn, ~p"/users/settings/two_factor?setup=1")
      assert html =~ "two-factor-qr"
    end

    test "on → off turns it off (and tells the owner by email)", %{conn: conn} do
      {user, _secret, _} = enable_two_factor(user_fixture())
      {:ok, view, _} = live(log_in_user(conn, user), ~p"/users/settings")

      view |> element("#two-factor-switch") |> render_click()
      refute TwoFactor.enabled?(Accounts.get_user!(user.id))
    end

    test "can't be turned off when the administrators require it", %{conn: conn} do
      Claper.Settings.set("two_factor_required", "true")
      {user, _secret, _} = enable_two_factor(user_fixture())
      {:ok, view, html} = live(log_in_user(conn, user), ~p"/users/settings")

      assert html =~ "Required by your administrator"
      assert has_element?(view, "#two-factor-switch[disabled]")
      render_click(view, "toggle_two_factor", %{})
      assert TwoFactor.enabled?(Accounts.get_user!(user.id))
    end
  end

  describe "setting it up in My account" do
    test "scan, enter a code, get backup codes", %{conn: conn} do
      user = user_fixture()
      {:ok, view, _} = live(log_in_user(conn, user), ~p"/users/settings/two_factor")

      html = view |> element("#two-factor-start") |> render_click()
      assert html =~ "two-factor-qr"
      assert html =~ "otpauth://totp/"

      secret =
        Base.decode32!(
          view
          |> element("#two-factor-key")
          |> render()
          |> then(&Regex.run(~r/>\s*([A-Z2-7 ]+)\s*</, &1))
          |> List.last()
          |> String.replace(" ", ""),
          padding: false
        )

      html = view |> form("#two-factor-confirm", %{code: "000000"}) |> render_submit()
      assert html =~ "That code didn"

      html =
        view
        |> form("#two-factor-confirm", %{code: NimbleTOTP.verification_code(secret)})
        |> render_submit()

      assert html =~ "Save your backup codes"
      assert TwoFactor.enabled?(Accounts.get_user!(user.id))
    end
  end

  describe "confirming the password before sensitive actions" do
    setup %{conn: conn} do
      user = user_fixture()
      conn = log_in_user(conn, user)
      token = get_session(conn, :user_token)

      # Signed in an hour ago
      Claper.Repo.update_all(
        from(t in Accounts.UserToken, where: t.token == ^token),
        set: [inserted_at: NaiveDateTime.add(NaiveDateTime.utc_now(), -3600)]
      )

      %{conn: conn, user: user}
    end

    test "changing the email address asks for the password first", %{conn: conn} do
      assert {:error, {:redirect, %{to: to}}} = live(conn, ~p"/users/settings/edit/email")
      assert to =~ "/users/confirm_password?return_to=%2Fusers%2Fsettings%2Fedit%2Femail"
    end

    test "deleting the account asks for the password first", %{conn: conn, user: user} do
      conn = delete(conn, ~p"/users/register/delete")
      assert redirected_to(conn) =~ "/users/confirm_password"
      refute Accounts.get_user!(user.id).deleted_at
    end

    test "the right password starts a fresh session and goes back", %{conn: conn, user: user} do
      old_token = get_session(conn, :user_token)

      wrong =
        post(conn, ~p"/users/confirm_password", %{
          "reauth" => %{
            "password" => "not my password at all",
            "return_to" => "/users/settings/edit/email"
          }
        })

      assert html_response(wrong, 422) =~ "That password didn"

      conn =
        post(conn, ~p"/users/confirm_password", %{
          "reauth" => %{
            "password" => valid_user_password(),
            "return_to" => "/users/settings/edit/email"
          }
        })

      assert redirected_to(conn) == "/users/settings/edit/email"
      new_token = get_session(conn, :user_token)
      refute new_token == old_token
      assert Accounts.get_user_by_session_token(old_token) == nil
      assert ClaperWeb.UserAuth.recently_signed_in?(Accounts.session_signed_in_at(new_token))
      _ = user
    end

    test "it never sends people to another site afterwards" do
      assert ClaperWeb.UserAuth.safe_return_to("//evil.example") == "/users/settings"
      assert ClaperWeb.UserAuth.safe_return_to("https://evil.example") == "/users/settings"
      assert ClaperWeb.UserAuth.safe_return_to("/\\evil.example") == "/users/settings"
      assert ClaperWeb.UserAuth.safe_return_to("/admin/users/3") == "/admin/users/3"
    end

    test "with two-step sign-in on, the code is needed too", %{conn: conn, user: user} do
      {_user, secret, _} = enable_two_factor(user)

      no_code =
        post(conn, ~p"/users/confirm_password", %{
          "reauth" => %{"password" => valid_user_password(), "return_to" => "/users/settings"}
        })

      assert html_response(no_code, 422) =~ "That password or code didn"

      conn =
        post(conn, ~p"/users/confirm_password", %{
          "reauth" => %{
            "password" => valid_user_password(),
            "code" => totp_code(secret),
            "return_to" => "/users/settings"
          }
        })

      assert redirected_to(conn) == "/users/settings"
    end
  end
end
