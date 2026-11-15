defmodule ClaperWeb.Privacy do
  @moduledoc """
  The privacy page's facts that depend on how this copy is set up
  (2026-11-15), so the page never names a service the copy doesn't use:

  - `url/0`: where privacy links go: the server's `PRIVACY_URL` when the
    organization has its own policy, otherwise the built-in `/privacy`.
  - `services/0`: the outside services that handle people's information,
    read from the server's settings (mail transport, the proxy header,
    presentation storage, single sign-on).
  - `retention_days/0`: from `RECORD_RETENTION_DAYS` (`Claper.Retention`).
  """
  use Gettext, backend: ClaperWeb.Gettext

  @doc "Where privacy links point."
  def url do
    case Application.get_env(:claper, :privacy_url) do
      url when is_binary(url) and url != "" -> url
      _ -> "/privacy"
    end
  end

  @doc "Days sign-in records are kept; 0 means they are kept."
  def retention_days, do: Claper.Retention.days()

  @doc "`{name, what it does}` for each outside service this copy uses."
  def services do
    [proxy(), mail(), storage(), sign_on()]
    |> Enum.reject(&is_nil/1)
  end

  defp proxy do
    headers = Application.get_env(:claper, :remote_ip_headers, [])

    if "cf-connecting-ip" in Enum.map(headers, &String.downcase/1),
      do:
        {"Cloudflare",
         gettext("carries all traffic between your browser and the app, and protects it")}
  end

  defp mail do
    case Application.get_env(:claper, Claper.Mailer, [])[:adapter] do
      Swoosh.Adapters.Resend ->
        {"Resend", gettext("sends the app's emails, such as sign-in and password emails")}

      Swoosh.Adapters.SMTP ->
        {gettext("An email server"), gettext("sends the app's emails")}

      _ ->
        nil
    end
  end

  defp storage do
    if Application.get_env(:claper, :presentations, [])[:storage] == "s3",
      do: {"Amazon S3", gettext("stores the presentation files facilitators upload")}
  end

  defp sign_on do
    oidc = Application.get_env(:claper, :oidc, [])

    if oidc[:enabled],
      do:
        {oidc[:provider_name] || gettext("A sign-in provider"),
         gettext("lets facilitators sign in with an account they already have")}
  end
end
