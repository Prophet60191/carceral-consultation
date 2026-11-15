defmodule ClaperWeb.ActivityText do
  @moduledoc """
  Audit Log entries as sentences for the person they're about (My account ›
  Sessions and activity, docs/SECURITY.md): "You signed in with your
  password and a code", "An administrator changed your role".
  """
  use Gettext, backend: ClaperWeb.Gettext

  alias Claper.Accounts.Administration

  @doc "The sentence for `log`, as seen by the account's owner."
  def describe(%{action: action, metadata: meta}) do
    meta = meta || %{}

    case action do
      "user.login" ->
        signed_in(meta["method"])

      "user.logout" ->
        gettext("You signed out")

      "user.login_failed" ->
        failed(meta["reason"])

      "user.login_paused" ->
        gettext("Sign-in was paused after too many failed tries")

      "user.new_device" ->
        gettext("You signed in from a new browser")

      "user.password_changed" ->
        gettext("You changed your password")

      "user.password_set" ->
        gettext("You set a password")

      "user.password_reset" ->
        gettext("You reset your password with an email link")

      "user.email_change_requested" ->
        gettext("You asked to change your email to %{email}", email: meta["new_email"])

      "user.email_changed" ->
        gettext("Your email changed from %{old} to %{new}",
          old: meta["old_email"],
          new: meta["new_email"]
        )

      "user.profile_updated" ->
        gettext("You changed your name")

      "user.identity_unlinked" ->
        gettext("You unlinked an outside account")

      "user.two_factor_enabled" ->
        gettext("You turned on two-step sign-in")

      "user.two_factor_disabled" ->
        gettext("You turned off two-step sign-in")

      "user.backup_codes_regenerated" ->
        gettext("You made new backup codes")

      "user.invitation_accepted" ->
        gettext("You accepted your invitation")

      "user.session_signed_out" ->
        gettext("You signed out another session")

      "user.other_sessions_signed_out" ->
        gettext("You signed out your other sessions")

      "user.account_deleted" ->
        gettext("You deleted your account")

      "admin.user_invited" ->
        gettext("An administrator invited you")

      "admin.invitation_resent" ->
        gettext("An administrator sent your invitation again")

      "admin.user_updated" ->
        gettext("An administrator changed your name")

      "admin.user_role_changed" ->
        role_changed(meta)

      "admin.email_change_sent" ->
        gettext("An administrator asked to change your email to %{email}",
          email: meta["new_email"]
        )

      "admin.invitation_email_corrected" ->
        gettext("An administrator corrected your email address")

      "admin.password_reset_sent" ->
        gettext("An administrator sent you a password reset link")

      "admin.user_signed_out_everywhere" ->
        gettext("An administrator signed you out everywhere")

      "admin.two_factor_reset" ->
        gettext("An administrator turned off your two-step sign-in")

      "admin.user_disabled" ->
        gettext("An administrator disabled your account")

      "admin.user_enabled" ->
        gettext("An administrator enabled your account")

      "security.rate_limit_exceeded" ->
        gettext("Too many requests came from your address")

      other ->
        other
    end
  end

  @doc "Where it came from: \"Chrome on macOS · 203.0.113.9\", or nil."
  def origin(%{metadata: meta}) do
    meta = meta || %{}
    browser = meta["user_agent"] && ClaperWeb.UserAgent.describe(meta["user_agent"])
    parts = Enum.reject([browser, meta["ip_address"]], &is_nil/1)
    if parts == [], do: nil, else: Enum.join(parts, " · ")
  end

  defp signed_in("password+code"), do: gettext("You signed in with your password and a code")

  defp signed_in("password+backup_code"),
    do: gettext("You signed in with your password and a backup code")

  defp signed_in("confirm_password"), do: gettext("You confirmed your password")
  defp signed_in("oidc"), do: gettext("You signed in through single sign-on")
  defp signed_in("lms"), do: gettext("You signed in from your LMS")
  defp signed_in("invitation"), do: gettext("You signed in after accepting your invitation")
  defp signed_in("email_link"), do: gettext("You signed in with an email link")
  defp signed_in("sign_up"), do: gettext("You signed up")
  defp signed_in(_), do: gettext("You signed in with your password")

  defp failed("wrong_code"), do: gettext("A sign-in failed: wrong code")
  defp failed("confirm_password_failed"), do: gettext("Confirming your password failed")
  defp failed(_), do: gettext("A sign-in failed: wrong password")

  defp role_changed(%{"from" => from, "to" => to}),
    do:
      gettext("An administrator changed your role from %{from} to %{to}",
        from: Administration.role_label(from),
        to: Administration.role_label(to)
      )

  defp role_changed(_), do: gettext("An administrator changed your role")
end
