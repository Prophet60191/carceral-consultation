defmodule ClaperWeb.AdminLive.AccountManagementTest do
  @moduledoc """
  Admin › Users: invitations, guards, changes taking effect at once
  (docs/SECURITY.md, "Managing accounts").
  """
  use ClaperWeb.ConnCase, async: false
  use Oban.Testing, repo: Claper.Repo

  import Phoenix.LiveViewTest
  import Claper.AccountsFixtures

  alias Claper.Accounts
  alias Claper.Accounts.{Administration, TwoFactor}
  alias Claper.Audit.Log
  alias Claper.Repo

  setup %{conn: conn} do
    for name <- ["user", "admin"] do
      _ = Accounts.get_role_by_name(name) || elem(Accounts.create_role(%{name: name}), 1)
    end

    {:ok, admin} = Accounts.assign_role(confirmed_user_fixture(), "admin")
    %{conn: log_in_user(conn, admin), admin: admin}
  end

  defp logs(action), do: Repo.all(from l in Log, where: l.action == ^action)

  # The links the emails carry (email jobs run inside the page's process)
  defp tokens(user, context) do
    Repo.all(
      from t in Accounts.UserToken, where: t.user_id == ^user.id and like(t.context, ^context)
    )
  end

  # Each request from its own address: the sign-in pages allow 10 a minute
  defp fresh_conn do
    n = System.unique_integer([:positive])

    Map.put(
      build_conn(),
      :remote_ip,
      {10, rem(div(n, 65_536), 256), rem(div(n, 256), 256), rem(n, 256)}
    )
  end

  defp role_id(name), do: Accounts.get_role_by_name(name).id

  defp signed_in_elsewhere(user) do
    token = Accounts.generate_user_session_token(user)
    assert Accounts.get_user_by_session_token(token)
    token
  end

  defp invite(attrs \\ %{}) do
    attrs =
      Map.merge(
        %{
          "email" => unique_user_email(),
          "first_name" => "Ada",
          "last_name" => "Lovelace",
          "role_id" => role_id("user")
        },
        attrs
      )

    {:ok, user} =
      Administration.invite(attrs, fn token -> send(self(), {:invite_token, token}) && "url" end)

    assert_received {:invite_token, token}
    {user, token}
  end

  describe "roles" do
    test "are called Administrator and Facilitator", %{conn: conn} do
      user = confirmed_user_fixture()
      {:ok, _view, html} = live(conn, ~p"/admin/users")
      assert html =~ "Administrator"
      assert html =~ "Facilitator"
      refute html =~ ">user<"
      _ = user
    end
  end

  describe "inviting" do
    test "the form has no password field and sends an invitation", %{conn: conn} do
      email = unique_user_email()
      {:ok, view, html} = live(conn, ~p"/admin/users/new")
      refute html =~ ~s(name="user[password]")

      view
      |> form("#user-form", %{
        "user" => %{
          "first_name" => "Ada",
          "last_name" => "Lovelace",
          "email" => email,
          "role_id" => role_id("user")
        }
      })
      |> render_submit()

      user = Accounts.get_user_by_email(email)
      assert Administration.invitation_pending?(user)
      assert user.is_randomized_password
      # The email went out with a link (the job runs in the page's process)
      assert [_] = tokens(user, "invitation")

      # The link is sealed in the stored job
      job =
        Claper.Workers.Mailers.new_invitation(user.id, "https://x/users/invitation/secret", "en")

      refute inspect(job.changes.args) =~ "secret"

      assert [_] = logs("admin.user_invited")
    end

    test "the invited person chooses a password (the usual rules) and is signed in; the link works once" do
      {user, token} = invite()

      page = fresh_conn() |> get(~p"/users/invitation/#{token}") |> html_response(200)
      assert page =~ "Choose your password"
      assert page =~ user.email

      # Browsers can suggest a strong password and save it for this account
      assert page =~ ~s(autocomplete="new-password")
      assert page =~ ~s(minlength="15")
      assert page =~ ~s(passwordrules="minlength: 15;")
      assert page =~ ~s(value="#{user.email}" autocomplete="username")
      # Each password field has its show/hide button
      assert page =~ ~s(aria-controls="user_password")
      assert page =~ ~s(aria-controls="user_password_confirmation")

      short =
        post(fresh_conn(), ~p"/users/invitation/#{token}", %{
          "user" => %{"password" => "too short", "password_confirmation" => "too short"}
        })

      assert html_response(short, 422) =~ "at least 15 characters"

      conn =
        post(fresh_conn(), ~p"/users/invitation/#{token}", %{
          "user" => %{
            "password" => "my own long sentence",
            "password_confirmation" => "my own long sentence"
          }
        })

      assert redirected_to(conn) == "/events"
      assert get_session(conn, :user_token)

      user = Accounts.get_user!(user.id)
      refute Administration.invitation_pending?(user)
      refute user.is_randomized_password
      assert Accounts.get_user_by_email_and_password(user.email, "my own long sentence")
      assert [_] = logs("user.invitation_accepted")

      again = fresh_conn() |> get(~p"/users/invitation/#{token}")
      assert redirected_to(again) == ~p"/users/log_in"
    end

    test "nobody can sign in with an invited account before it's accepted" do
      {user, _token} = invite()
      refute Accounts.get_user_by_email_and_password(user.email, "")
      refute Accounts.get_user_by_email_and_password(user.email, valid_user_password())
    end

    test "sending it again replaces the old link", %{conn: conn} do
      {user, old_token} = invite()
      {:ok, view, _} = live(conn, ~p"/admin/users/#{user}")
      view |> element("#resend-invitation") |> render_click()

      assert Administration.get_invited_user(old_token) == nil
      assert [_] = logs("admin.invitation_resent")
    end
  end

  describe "guards (checked on the server)" do
    test "an administrator can't disable or delete themselves", %{conn: conn, admin: admin} do
      {:ok, view, html} = live(conn, ~p"/admin/users/#{admin}")
      refute html =~ ~s(phx-click="disable")
      assert html =~ "You can&#39;t disable or delete your own account here."

      render_click(view, "disable", %{"id" => to_string(admin.id)})
      render_click(view, "delete", %{"id" => to_string(admin.id)})
      refute Accounts.get_user!(admin.id).deleted_at
    end

    test "an administrator can't change their own role", %{conn: conn, admin: admin} do
      {:ok, view, html} = live(conn, ~p"/admin/users/#{admin}/edit")
      assert html =~ "You can&#39;t change your own role"
      refute has_element?(view, "#user_role_id")
      assert {:error, _} = Administration.check(admin, admin, {:set_role, role_id("user")})
    end

    test "the last active administrator can't be demoted, disabled or deleted" do
      {:ok, only_admin} = Accounts.assign_role(confirmed_user_fixture(), "admin")
      someone = confirmed_user_fixture()

      # Every other administrator gone
      Repo.update_all(
        from(u in Accounts.User, where: u.id != ^only_admin.id and not is_nil(u.role_id)),
        set: [deleted_at: NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)]
      )

      for action <- [:disable, :delete, {:set_role, role_id("user")}] do
        assert {:error, message} = Administration.check(someone, only_admin, action)
        assert message =~ "last administrator"
      end

      assert :ok = Administration.check(someone, only_admin, {:set_role, role_id("admin")})
    end
  end

  describe "changes take effect at once" do
    test "a new role signs them out everywhere", %{conn: conn} do
      target = confirmed_user_fixture()
      token = signed_in_elsewhere(target)
      {:ok, view, _} = live(conn, ~p"/admin/users/#{target}/edit")

      view
      |> form("#user-form", %{
        "user" => %{
          "first_name" => target.first_name,
          "last_name" => target.last_name,
          "email" => target.email,
          "role_id" => role_id("admin")
        }
      })
      |> render_submit()

      assert Accounts.get_user!(target.id).role_id == role_id("admin")
      assert Accounts.get_user_by_session_token(token) == nil
      assert [log] = logs("admin.user_role_changed")
      assert log.metadata["from"] == "user" and log.metadata["to"] == "admin"
    end

    test "disabling signs them out everywhere", %{conn: conn} do
      target = confirmed_user_fixture()
      token = signed_in_elsewhere(target)
      {:ok, view, _} = live(conn, ~p"/admin/users/#{target}")
      render_click(view, "disable", %{"id" => to_string(target.id)})

      assert Repo.get_by(Accounts.UserToken, token: token) == nil
    end

    test "a new email address waits for its owner to confirm it", %{conn: conn} do
      target = confirmed_user_fixture()
      {:ok, view, _} = live(conn, ~p"/admin/users/#{target}/edit")

      view
      |> form("#user-form", %{
        "user" => %{
          "first_name" => target.first_name,
          "last_name" => target.last_name,
          "email" => "new-address@example.org",
          "role_id" => target.role_id
        }
      })
      |> render_submit()

      assert Accounts.get_user!(target.id).email == target.email
      assert [token] = tokens(target, "change:%")
      assert token.sent_to == "new-address@example.org"

      assert [_] = logs("admin.email_change_sent")
    end

    test "for an invitation not yet accepted, the email is corrected and the invitation re-sent",
         %{conn: conn} do
      {user, old_token} = invite()
      {:ok, view, _} = live(conn, ~p"/admin/users/#{user}/edit")

      view
      |> form("#user-form", %{
        "user" => %{
          "first_name" => user.first_name,
          "last_name" => user.last_name,
          "email" => "corrected@example.org",
          "role_id" => user.role_id
        }
      })
      |> render_submit()

      assert Accounts.get_user!(user.id).email == "corrected@example.org"
      assert Administration.get_invited_user(old_token) == nil
    end
  end

  describe "access buttons" do
    test "sign out everywhere", %{conn: conn} do
      target = confirmed_user_fixture()
      token = signed_in_elsewhere(target)
      {:ok, view, html} = live(conn, ~p"/admin/users/#{target}")
      assert html =~ ~s(id="open-sessions">1<)

      view |> element("#sign-out-everywhere") |> render_click()
      assert Accounts.get_user_by_session_token(token) == nil
      assert [log] = logs("admin.user_signed_out_everywhere")
      assert log.metadata["sessions"] == 1
    end

    test "send a password reset link", %{conn: conn} do
      target = confirmed_user_fixture()
      {:ok, view, _} = live(conn, ~p"/admin/users/#{target}")

      view |> element("#send-reset") |> render_click()
      assert [_] = tokens(target, "reset_password")
      assert [_] = logs("admin.password_reset_sent")
    end

    test "turn off someone's two-step sign-in", %{conn: conn} do
      {target, _secret, _} = enable_two_factor(confirmed_user_fixture())
      token = signed_in_elsewhere(target)
      {:ok, view, _} = live(conn, ~p"/admin/users/#{target}")

      view |> element("#reset-two-factor") |> render_click()
      refute TwoFactor.enabled?(Accounts.get_user!(target.id))
      assert Accounts.get_user_by_session_token(token) == nil
      assert [_] = logs("admin.two_factor_reset")
    end
  end
end
