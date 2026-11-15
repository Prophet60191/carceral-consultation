defmodule ClaperWeb.AccountAuditTest do
  @moduledoc """
  The Audit Log's account and administration events, and the new-device
  email (docs/SECURITY.md).
  """
  use ClaperWeb.ConnCase, async: false
  use Oban.Testing, repo: Claper.Repo

  import Phoenix.LiveViewTest
  import Claper.AccountsFixtures

  alias Claper.Accounts
  alias Claper.Audit.Log
  alias Claper.Repo

  setup do
    for name <- ["user", "admin"] do
      _ = Accounts.get_role_by_name(name) || elem(Accounts.create_role(%{name: name}), 1)
    end

    :ok
  end

  # Each request from its own address, so the per-address sign-in limit
  # (10 a minute) doesn't get in the way
  defp fresh_conn do
    n = System.unique_integer([:positive])

    Map.put(
      build_conn(),
      :remote_ip,
      {10, rem(div(n, 65_536), 256), rem(div(n, 256), 256), rem(n, 256)}
    )
  end

  defp logs(action), do: Repo.all(from l in Log, where: l.action == ^action, order_by: l.id)

  defp sign_in(conn, email, password) do
    post(conn, ~p"/users/log_in", %{"user" => %{"email" => email, "password" => password}})
  end

  describe "sign-in" do
    test "a wrong password is logged on the account, without the password" do
      user = user_fixture()
      sign_in(fresh_conn(), user.email, "the wrong sentence entirely")

      assert [log] = logs("user.login_failed")
      assert log.user_id == user.id
      assert log.metadata["reason"] == "wrong_password"
      assert log.metadata["ip_address"]
      refute Jason.encode!(log.metadata) =~ "wrong sentence"
    end

    test "tries at addresses with no account aren't logged (people sometimes type a password there)" do
      sign_in(fresh_conn(), "a quiet lake at dawn", "whatever it was")
      assert logs("user.login_failed") == []
    end

    test "the account reaching its limit is logged once" do
      user = user_fixture()

      for i <- 1..12,
          do:
            sign_in(
              Map.put(build_conn(), :remote_ip, {198, 51, 100, i}),
              user.email,
              "wrong #{i} again"
            )

      assert [_] = logs("user.login_paused")
      assert length(logs("user.login_failed")) == 10
    end

    test "each sign-in says how it happened" do
      user = user_fixture()
      sign_in(fresh_conn(), user.email, valid_user_password())

      {user2, secret, _} = enable_two_factor(user_fixture())
      conn = sign_in(fresh_conn(), user2.email, valid_user_password())

      conn
      |> recycle()
      |> post(~p"/users/two_factor", %{"two_factor" => %{"code" => totp_code(secret)}})

      # Sign-ins are written in the background
      Process.sleep(200)
      methods = logs("user.login") |> Enum.map(& &1.metadata["method"])
      assert "password" in methods
      assert "password+code" in methods
    end
  end

  describe "changes to one's own account" do
    test "password change and two-step sign-in are logged", %{conn: conn} do
      user = user_fixture()
      conn = log_in_user(conn, user)

      {:ok, view, _} = live(conn, ~p"/users/settings/edit/password")

      view
      |> form("#update_password", %{
        "user" => %{
          "current_password" => valid_user_password(),
          "password" => "a whole new sentence now"
        }
      })
      |> render_submit()

      assert [log] = logs("user.password_changed")
      assert log.user_id == user.id
      refute Jason.encode!(log.metadata) =~ "sentence"

      {:ok, view, _} = live(log_in_user(fresh_conn(), user), ~p"/users/settings/two_factor")
      view |> element("#two-factor-start") |> render_click()
      [_, key] = Regex.run(~r/id="two-factor-key"[^>]*>\s*([A-Z2-7 ]+)\s*</, render(view))
      secret = Base.decode32!(String.replace(key, " ", ""), padding: false)

      view
      |> form("#two-factor-confirm", %{code: NimbleTOTP.verification_code(secret)})
      |> render_submit()

      assert [_] = logs("user.two_factor_enabled")
    end
  end

  describe "administrators' actions" do
    setup %{conn: conn} do
      {:ok, admin} = Accounts.assign_role(user_fixture(), "admin")
      %{conn: log_in_user(conn, admin), admin: admin}
    end

    test "editing a user: which fields and the role change, logged as the admin acting on them",
         %{conn: conn, admin: admin} do
      target = user_fixture()
      admin_role = Accounts.get_role_by_name("admin")
      {:ok, view, _} = live(conn, ~p"/admin/users/#{target}/edit")

      view
      |> form("#user-form", %{
        "user" => %{
          "first_name" => "Renamed",
          "last_name" => target.last_name,
          "email" => target.email,
          "role_id" => admin_role.id
        }
      })
      |> render_submit()

      assert [updated] = logs("admin.user_updated")
      assert updated.user_id == admin.id
      assert updated.resource_type == "user" and updated.resource_id == target.id
      assert updated.metadata["fields"] =~ "first_name"

      assert [role] = logs("admin.user_role_changed")
      assert role.metadata["to"] == "admin"
    end

    test "disabling and deleting users", %{conn: conn} do
      target = user_fixture()
      {:ok, view, _} = live(conn, ~p"/admin/users/#{target}")
      render_click(view, "disable", %{"id" => to_string(target.id)})
      assert [log] = logs("admin.user_disabled")
      assert log.metadata["target_email"] == target.email

      {:ok, view, _} = live(conn, ~p"/admin/users/#{target}")
      render_click(view, "delete", %{"id" => to_string(target.id)})
      assert [deleted] = logs("admin.user_deleted")
      assert deleted.metadata["target_email"] == target.email
    end

    test "the brand and settings", %{conn: conn} do
      {:ok, view, _} = live(conn, ~p"/admin/brand")
      view |> form("#brand-identity-form", brand: %{name: "Northside"}) |> render_submit()
      assert [brand] = logs("admin.brand_updated")
      assert brand.metadata["name"] == "Northside"
      Claper.Branding.clear_cache()

      # Last: once it's required, this administrator (without two-step
      # sign-in) is sent to set it up
      {:ok, view, _} = live(conn, ~p"/admin/settings")

      view
      |> form("#security-settings-form", %{"two_factor_required" => "true"})
      |> render_submit()

      assert [log] = logs("admin.settings_changed")
      assert log.metadata["two_factor_required"] == true
    end
  end

  describe "new-device email" do
    defp device_cookie(conn), do: conn.resp_cookies["_cc_device"]

    test "an account's first browser is quiet; a new one emails the owner; a known one doesn't" do
      user = user_fixture()

      Oban.Testing.with_testing_mode(:manual, fn ->
        first = sign_in(fresh_conn(), user.email, valid_user_password())
        assert %{value: _} = device_cookie(first)
        refute_enqueued(worker: Claper.Workers.Mailers, args: %{"type" => "new_device"})

        # The same browser again
        again =
          fresh_conn()
          |> put_req_cookie("_cc_device", device_cookie(first).value)
          |> sign_in(user.email, valid_user_password())

        assert again.resp_cookies["_cc_device"] == nil
        refute_enqueued(worker: Claper.Workers.Mailers, args: %{"type" => "new_device"})

        # Another browser
        build_conn()
        |> put_req_header(
          "user-agent",
          "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1"
        )
        |> sign_in(user.email, valid_user_password())

        assert_enqueued(
          worker: Claper.Workers.Mailers,
          args: %{"type" => "new_device", "user_id" => user.id, "browser" => "Safari on iPhone"}
        )
      end)

      assert [log] = logs("user.new_device")
      assert log.metadata["browser"] == "Safari on iPhone"
    end

    test "the email says when, which browser and from where, and what to do" do
      user = user_fixture()

      email =
        ClaperWeb.Notifiers.UserNotifier.new_device(user, %{
          "browser" => "Chrome on Windows",
          "ip_address" => "203.0.113.9",
          "signed_in_at" => "2026-11-15T04:12:00Z"
        })

      assert email.to == [{"", user.email}]
      assert email.subject =~ "New sign-in"
      assert email.html_body =~ "Chrome on Windows"
      assert email.html_body =~ "203.0.113.9"
      assert email.html_body =~ "15 November 2026, 04:12 UTC"
      assert email.html_body =~ "/users/reset_password"
    end
  end

  test "user agents in words" do
    describe = &ClaperWeb.UserAgent.describe/1

    assert describe.(
             "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36"
           ) ==
             "Chrome on macOS"

    assert describe.(
             "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36 Edg/131.0.0.0"
           ) ==
             "Edge on Windows"

    assert describe.("Mozilla/5.0 (X11; Linux x86_64; rv:133.0) Gecko/20100101 Firefox/133.0") ==
             "Firefox on Linux"

    assert describe.(nil) == "Unknown browser"
  end
end
