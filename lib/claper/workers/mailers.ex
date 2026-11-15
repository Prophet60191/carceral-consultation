defmodule Claper.Workers.Mailers do
  use Oban.Worker, queue: :mailers

  alias Claper.Mailer
  alias ClaperWeb.Notifiers.{EventNotifier, LeaderNotifier, UserNotifier}

  # Links that sign someone in or change their account (reset password,
  # confirm, change email, magic link, OIDC confirmation) carry a secret.
  # Job arguments are stored in the database for a week and written to the
  # log, so these links are kept sealed (encrypted with the app's secret key)
  # until the email is built (docs/SECURITY.md).
  @link_salt "mail link"
  # Longer than any job's retries, and than the longest-lived link (7 days)
  @link_max_age 60 * 60 * 24 * 8

  @impl Oban.Worker
  def perform(%Oban.Job{args: args}) do
    # Jobs still queued from before an upgrade have no locale in their args.
    locale = Map.get(args, "locale", Gettext.get_locale(ClaperWeb.Gettext))

    case open_link(args) do
      {:ok, args} -> deliver(args, locale)
      # Can't be opened (e.g. the secret key changed): retrying won't help
      :error -> {:cancel, :unreadable_link}
    end
  end

  defp deliver(args, locale) do
    email = Gettext.with_locale(ClaperWeb.Gettext, locale, fn -> build_email(args) end)
    Mailer.deliver(email)
  end

  @doc false
  def seal_link(url), do: Phoenix.Token.encrypt(ClaperWeb.Endpoint, @link_salt, url)

  defp open_link(%{"sealed_url" => sealed} = args) do
    case Phoenix.Token.decrypt(ClaperWeb.Endpoint, @link_salt, sealed, max_age: @link_max_age) do
      {:ok, url} -> {:ok, args |> Map.delete("sealed_url") |> Map.put("url", url)}
      {:error, _} -> :error
    end
  end

  # Jobs queued before links were sealed, and links without a secret
  defp open_link(args), do: {:ok, args}

  defp build_email(%{"type" => type, "user_id" => user_id, "url" => url})
       when type in ["confirm", "reset"] do
    user = Claper.Accounts.get_user!(user_id)

    case type do
      "confirm" -> UserNotifier.confirm(user, url)
      "reset" -> UserNotifier.reset(user, url)
    end
  end

  defp build_email(%{"type" => "security_notice", "email" => email, "kind" => kind} = args) do
    UserNotifier.security_notice(email, kind, args["details"] || %{})
  end

  defp build_email(%{"type" => "invitation", "user_id" => user_id, "url" => url}) do
    UserNotifier.invitation(Claper.Accounts.get_user!(user_id), url)
  end

  defp build_email(%{"type" => "new_device", "user_id" => user_id} = args) do
    UserNotifier.new_device(Claper.Accounts.get_user!(user_id), args)
  end

  defp build_email(%{"type" => "update_email", "new_email" => new_email, "url" => url}) do
    UserNotifier.update_email(new_email, url)
  end

  defp build_email(%{"type" => "magic", "email" => email, "url" => url}) do
    UserNotifier.magic(email, url)
  end

  defp build_email(%{
         "type" => "oidc_confirmation",
         "email" => email,
         "provider" => provider,
         "url" => url
       }) do
    UserNotifier.oidc_confirmation(email, provider, url)
  end

  defp build_email(%{"type" => "welcome", "email" => email}) do
    UserNotifier.welcome(email)
  end

  defp build_email(%{
         "type" => "event_invitation",
         "event_name" => event_name,
         "email" => email,
         "url" => url
       }) do
    LeaderNotifier.event_invitation(event_name, email, url)
  end

  defp build_email(%{"type" => "event_recap", "event_id" => event_id, "ended_by" => ended_by}) do
    event = Claper.Events.get_event!(event_id, [:user])

    inactivity_days = if ended_by == "inactivity", do: Claper.Events.inactivity_days()

    EventNotifier.recap(event, Claper.Stats.report_summary(event), inactivity_days)
  end

  # Helper functions to create jobs
  def new_confirmation(user_id, url, locale) do
    new(%{type: "confirm", user_id: user_id, sealed_url: seal_link(url), locale: locale})
  end

  def new_reset_password(user_id, url, locale) do
    new(%{type: "reset", user_id: user_id, sealed_url: seal_link(url), locale: locale})
  end

  def new_update_email(new_email, url, locale) do
    new(%{
      type: "update_email",
      new_email: new_email,
      sealed_url: seal_link(url),
      locale: locale
    })
  end

  def new_magic_link(email, url, locale) do
    new(%{type: "magic", email: email, sealed_url: seal_link(url), locale: locale})
  end

  def new_oidc_confirmation(email, provider, url, locale) do
    new(%{
      type: "oidc_confirmation",
      email: email,
      provider: provider,
      sealed_url: seal_link(url),
      locale: locale
    })
  end

  @doc "A change to someone's account they should know about (Claper.Accounts.SecurityNotices)."
  def new_security_notice(email, kind, details, locale) do
    new(%{type: "security_notice", email: email, kind: kind, details: details, locale: locale})
  end

  @doc "An administrator's invitation: the link sets a password, so it's sealed."
  def new_invitation(user_id, url, locale) do
    new(%{type: "invitation", user_id: user_id, sealed_url: seal_link(url), locale: locale})
  end

  @doc "Someone signed in to this account from a browser it hasn't used before."
  def new_device(user_id, browser, ip_address, signed_in_at, locale) do
    new(%{
      type: "new_device",
      user_id: user_id,
      browser: browser,
      ip_address: ip_address,
      signed_in_at: signed_in_at,
      locale: locale
    })
  end

  def new_welcome(email, locale) do
    new(%{type: "welcome", email: email, locale: locale})
  end

  def event_invitation(event_name, email, url, locale) do
    new(%{
      type: "event_invitation",
      event_name: event_name,
      email: email,
      url: url,
      locale: locale
    })
  end

  def new_event_recap(event_id, ended_by, locale) when ended_by in [:manual, :inactivity] do
    new(%{type: "event_recap", event_id: event_id, ended_by: ended_by, locale: locale})
  end
end
