defmodule Claper.AccountsFixtures do
  @moduledoc """
  This module defines test helpers for creating
  entities via the `Claper.Accounts` context.
  """

  def unique_user_email, do: "user#{System.unique_integer()}@example.com"
  def valid_user_password, do: "a quiet lake at dawn"

  def valid_user_attributes(attrs \\ %{}) do
    attrs = Enum.into(attrs, %{})
    password = Map.get(attrs, :password, valid_user_password())

    attrs
    |> Enum.into(%{
      email: unique_user_email(),
      first_name: "John",
      last_name: "Doe",
      password: password,
      confirmed_at: NaiveDateTime.utc_now()
    })
    |> Map.put_new(:password_confirmation, password)
  end

  def no_valid_user_attributes(attrs \\ %{}) do
    attrs = Enum.into(attrs, %{})
    password = Map.get(attrs, :password, valid_user_password())

    attrs
    |> Enum.into(%{
      email: unique_user_email(),
      first_name: "John",
      last_name: "Doe",
      password: password
    })
    |> Map.put_new(:password_confirmation, password)
  end

  def user_fixture(attrs \\ %{}) do
    {:ok, user} =
      attrs
      |> no_valid_user_attributes()
      |> Claper.Accounts.register_user()

    user
  end

  def confirmed_user_fixture(attrs \\ %{}) do
    {:ok, user} =
      attrs
      |> valid_user_attributes()
      |> Claper.Accounts.register_user()

    user
  end

  @doc """
  Turns on two-step sign-in for `user` with a known secret. Returns
  `{user, secret, backup_codes}`; `totp_code(secret)` gives a valid code.
  """
  def enable_two_factor(user) do
    secret = NimbleTOTP.secret()
    # A code from a minute ago: the real sign-in's code is still unused
    code = NimbleTOTP.verification_code(secret, time: System.os_time(:second) - 60)

    {:ok, user, codes} =
      Claper.Accounts.TwoFactor.enable(user, secret, code, System.os_time(:second) - 60)

    {user, secret, codes}
  end

  def totp_code(secret), do: NimbleTOTP.verification_code(secret)
end
