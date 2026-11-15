defmodule Claper.Accounts.SecurityNotices do
  @moduledoc """
  Emails telling someone their account changed, so a takeover doesn't go
  unnoticed (docs/SECURITY.md, "Security notices"):

  - `:email_changed`: sent to the **old** address (the new one is the
    attacker's, if it's an attack)
  - `:password_changed`: changed in My account, reset by link, or set
  - `:two_factor_off`: turned off by them or by an administrator

  No links with secrets in them: only where to go next.
  """
  alias Claper.Accounts.User
  alias Claper.Workers.Mailers

  def email_changed(%User{} = user, old_email, new_email),
    do: notify(old_email, "email_changed", %{new_email: new_email}, user)

  def password_changed(%User{} = user, how) when how in [:changed, :reset, :set],
    do: notify(user.email, "password_changed", %{how: Atom.to_string(how)}, user)

  def two_factor_off(%User{} = user, by) when by in [:self, :admin],
    do: notify(user.email, "two_factor_off", %{by: Atom.to_string(by)}, user)

  defp notify(to, kind, details, user) do
    Mailers.new_security_notice(to, kind, details, user.locale || "en")
    |> Oban.insert()

    :ok
  end
end
