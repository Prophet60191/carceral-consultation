defmodule Claper.Accounts.TwoFactorTest do
  @moduledoc "Two-step sign-in (docs/SECURITY.md)."
  use Claper.DataCase, async: false

  import Claper.AccountsFixtures

  alias Claper.Accounts
  alias Claper.Accounts.TwoFactor

  setup do
    for name <- ["user", "admin"] do
      _ = Accounts.get_role_by_name(name) || elem(Accounts.create_role(%{name: name}), 1)
    end

    :ok
  end

  test "turns on only with a code from the new secret, and gives 10 backup codes" do
    user = user_fixture()
    secret = TwoFactor.new_secret()

    assert {:error, :invalid_code} = TwoFactor.enable(user, secret, "000000")
    refute TwoFactor.enabled?(Accounts.get_user!(user.id))

    assert {:ok, user, codes} =
             TwoFactor.enable(user, secret, NimbleTOTP.verification_code(secret))

    assert TwoFactor.enabled?(user)
    assert length(codes) == 10
    assert Enum.all?(codes, &(&1 =~ ~r/^[a-z2-9]{5}-[a-z2-9]{5}$/))
    assert length(Enum.uniq(codes)) == 10
  end

  test "the secret is stored encrypted and backup codes only as hashes" do
    {user, secret, codes} = enable_two_factor(user_fixture())

    refute user.totp_secret == secret
    refute user.totp_secret =~ Base.encode32(secret, padding: false)
    for code <- codes, do: refute(code in user.backup_code_hashes)
  end

  test "a code works once; the one from 30 seconds before still works" do
    {user, secret, _codes} = enable_two_factor(user_fixture())
    code = totp_code(secret)

    assert {:ok, user, :totp} = TwoFactor.verify(user, code)
    assert :error = TwoFactor.verify(user, code)

    {user2, secret2, _} = enable_two_factor(user_fixture())
    earlier = NimbleTOTP.verification_code(secret2, time: System.os_time(:second) - 30)
    assert {:ok, _, :totp} = TwoFactor.verify(user2, earlier)
    _ = user
  end

  test "a backup code works once, typed with capitals, spaces or no dash" do
    {user, _secret, [code | _]} = enable_two_factor(user_fixture())
    typed = code |> String.upcase() |> String.replace("-", " ")

    assert {:ok, user, :backup_code} = TwoFactor.verify(user, typed)
    assert TwoFactor.backup_codes_left(user) == 9
    assert :error = TwoFactor.verify(user, code)
  end

  test "new backup codes replace the old ones" do
    {user, _secret, [old | _]} = enable_two_factor(user_fixture())
    {:ok, user, [new | _]} = TwoFactor.regenerate_backup_codes(user)

    assert :error = TwoFactor.verify(user, old)
    assert {:ok, _, :backup_code} = TwoFactor.verify(user, new)
  end

  test "turning it off clears everything" do
    {user, secret, _} = enable_two_factor(user_fixture())
    {:ok, user} = TwoFactor.disable(user)

    refute TwoFactor.enabled?(user)
    assert user.backup_code_hashes == []
    assert :error = TwoFactor.verify(user, totp_code(secret))
  end

  test "each person chooses, unless the administrators require it for everyone" do
    user = user_fixture()
    {:ok, admin} = Accounts.assign_role(user_fixture(), "admin")

    refute TwoFactor.required?(user)
    refute TwoFactor.required?(admin)

    Claper.Settings.set("two_factor_required", "true")
    assert TwoFactor.required?(user)
    assert TwoFactor.required?(admin)
    assert TwoFactor.setup_needed?(admin)
  end

  test "the server can turn it off for someone locked out" do
    {user, _secret, _} = enable_two_factor(user_fixture())
    {:ok, _} = TwoFactor.disable(Accounts.get_user_by_email(user.email))
    refute TwoFactor.enabled?(Accounts.get_user!(user.id))
  end
end
