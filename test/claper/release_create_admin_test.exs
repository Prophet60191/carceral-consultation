defmodule Claper.ReleaseCreateAdminTest do
  @moduledoc "A new copy's first administrator is invited, never given a default password."
  use Claper.DataCase, async: false

  import ExUnit.CaptureIO

  alias Claper.Accounts
  alias Claper.Accounts.Administration

  setup do
    for name <- ["user", "admin"] do
      _ = Accounts.get_role_by_name(name) || elem(Accounts.create_role(%{name: name}), 1)
    end

    :ok
  end

  test "invites an administrator and prints a working one-time link" do
    output =
      capture_io(fn ->
        assert {:ok, url} = Claper.Release.create_admin("first-admin@example.org")
        send(self(), {:url, url})
      end)

    assert_received {:url, url}
    assert output =~ "Administrator invited: first-admin@example.org"
    assert output =~ url
    assert url =~ "/users/invitation/"

    user = Accounts.get_user_by_email("first-admin@example.org")
    assert Accounts.get_role_by_name("admin").id == user.role_id
    assert Administration.invitation_pending?(user)

    token = url |> String.split("/") |> List.last()
    assert %Accounts.User{id: id} = Administration.get_invited_user(token)
    assert id == user.id
  end

  test "seeds no longer create a default account" do
    refute File.read!("priv/repo/seeds.exs") =~ ~s(password: "claper")
  end
end
