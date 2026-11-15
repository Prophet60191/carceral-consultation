defmodule ClaperWeb.Notifiers.UserNotifier do
  use Phoenix.Swoosh, view: ClaperWeb.UserNotifierView, layout: {ClaperWeb.LayoutView, :email}
  use Gettext, backend: ClaperWeb.Gettext

  def magic(email, url) do
    new()
    |> to(email)
    |> from(Claper.Branding.mail_from())
    |> subject(gettext("Connect to %{name}", name: Claper.Branding.name(Claper.Branding.get())))
    |> render_body("magic.html", %{url: url})
  end

  def oidc_confirmation(email, provider, url) do
    new()
    |> to(email)
    |> from(Claper.Branding.mail_from())
    |> subject(
      gettext("Confirm your sign-in to %{name}",
        name: Claper.Branding.name(Claper.Branding.get())
      )
    )
    |> render_body("oidc_confirmation.html", %{provider: provider, url: url})
  end

  def welcome(email) do
    new()
    |> to(email)
    |> from(Claper.Branding.mail_from())
    |> subject(gettext("Next steps to boost your presentations"))
    |> render_body("welcome.html", %{email: email})
  end

  def update_email(new_email, url) do
    new()
    |> to(new_email)
    |> from(Claper.Branding.mail_from())
    |> subject(gettext("Update email instructions"))
    |> render_body("change.html", %{url: url})
  end

  @doc "A change to the account its owner should know about (Claper.Accounts.SecurityNotices)."
  def security_notice(email, kind, details) do
    name = Claper.Branding.name(Claper.Branding.get())
    base = ClaperWeb.Endpoint.url()

    {subject, heading, lines, button} =
      case {kind, details} do
        {"email_changed", %{"new_email" => new_email}} ->
          {gettext("Your %{name} email address was changed", name: name),
           gettext("Your email address was changed"),
           [
             gettext("The email address for your %{name} account is now %{email}.",
               name: name,
               email: new_email
             ),
             gettext(
               "If you didn't do this, someone else may have your account. Contact whoever runs %{name} right away; this address can no longer reset the password.",
               name: name
             )
           ], nil}

        {"password_changed", _} ->
          {gettext("Your %{name} password was changed", name: name),
           gettext("Your password was changed"),
           [
             gettext("The password for your %{name} account was just changed.", name: name),
             gettext("If you didn't do this, reset it now and turn on two-step sign-in.")
           ], {gettext("Reset password"), base <> "/users/reset_password"}}

        {"two_factor_off", %{"by" => "admin"}} ->
          {gettext("Two-step sign-in was turned off on your %{name} account", name: name),
           gettext("Two-step sign-in was turned off"),
           [
             gettext(
               "An administrator turned off two-step sign-in on your account, usually because you asked after losing your phone."
             ),
             gettext(
               "Set it up again from My account. If you didn't ask for this, tell them now."
             )
           ], {gettext("Set up two-step sign-in"), base <> "/users/settings/two_factor"}}

        {"two_factor_off", _} ->
          {gettext("Two-step sign-in was turned off on your %{name} account", name: name),
           gettext("Two-step sign-in was turned off"),
           [
             gettext("Your password is now the only thing protecting your account."),
             gettext("If you didn't do this, reset your password now and turn it back on.")
           ], {gettext("Reset password"), base <> "/users/reset_password"}}
      end

    new()
    |> to(email)
    |> from(Claper.Branding.mail_from())
    |> subject(subject)
    |> render_body("security_notice.html", %{heading: heading, lines: lines, button: button})
  end

  @doc "An administrator invited this person; the link sets their password."
  def invitation(user, url) do
    name = Claper.Branding.name(Claper.Branding.get())

    new()
    |> to(user.email)
    |> from(Claper.Branding.mail_from())
    |> subject(gettext("You're invited to %{name}", name: name))
    |> render_body("invitation.html", %{
      name: name,
      first_name: user.first_name,
      role: Claper.Accounts.Administration.role_label(Claper.Repo.preload(user, :role)),
      url: url
    })
  end

  @doc "Someone signed in from a browser this account hasn't used (docs/SECURITY.md)."
  def new_device(user, details) do
    name = Claper.Branding.name(Claper.Branding.get())

    new()
    |> to(user.email)
    |> from(Claper.Branding.mail_from())
    |> subject(gettext("New sign-in to your %{name} account", name: name))
    |> render_body("new_device.html", %{
      name: name,
      browser: details["browser"],
      ip_address: details["ip_address"],
      signed_in_at: format_time(details["signed_in_at"]),
      reset_url: ClaperWeb.Endpoint.url() <> "/users/reset_password",
      security_url: ClaperWeb.Endpoint.url() <> "/users/settings/two_factor"
    })
  end

  # "15 November 2026, 04:12 UTC" (the reader's time zone isn't known)
  defp format_time(iso) do
    case DateTime.from_iso8601(iso || "") do
      {:ok, at, _} -> Calendar.strftime(at, "%-d %B %Y, %H:%M UTC")
      _ -> iso
    end
  end

  def confirm(user, url) do
    new()
    |> to(user.email)
    |> from(Claper.Branding.mail_from())
    |> subject(gettext("Confirmation instructions"))
    |> render_body("confirm.html", %{user: user, url: url})
  end

  def reset(user, url) do
    new()
    |> to(user.email)
    |> from(Claper.Branding.mail_from())
    |> subject(gettext("Reset password instructions"))
    |> render_body("reset.html", %{user: user, url: url})
  end
end
