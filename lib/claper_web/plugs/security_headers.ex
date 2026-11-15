defmodule ClaperWeb.Plugs.SecurityHeaders do
  @moduledoc """
  Security headers on every response (docs/SECURITY.md).

  - **Content-Security-Policy**: which sources a page may load from. Scripts
    come only from the app itself (plus the theme script, allowed by its
    hash), so a script slipped into the page by an attacker won't run. Styles
    may be inline (the app sets `style=` attributes). Images, frames and
    media may come from any https address: presentations embed other
    websites, videos and images by design. Plugins, `<base>` changes and
    forms posting elsewhere are refused.
  - **frame-ancestors** follows the page's `X-Frame-Options`: pages that may
    be embedded (the attendee page, for LMSs) stay embeddable, the rest only
    within the app.
  - **Strict-Transport-Security** (HSTS) when the app is served over https
    (`hsts: true` from config/runtime.exs): browsers then never use plain
    http for it.
  - **Permissions-Policy**: no camera, location, payment or USB access; the
    microphone only for the app itself (live transcription).
  - **X-Robots-Tag: noindex, nofollow**: search engines leave the app out
    (the organization's own website is what people should find; event pages
    shouldn't appear in searches). `ALLOW_SEARCH_INDEXING=true` lets them in.
  """
  @behaviour Plug

  import Plug.Conn

  alias ClaperWeb.ThemeScript

  @hsts "max-age=31536000; includeSubDomains"
  @permissions "camera=(), geolocation=(), payment=(), usb=(), microphone=(self)"

  @impl true
  def init(opts), do: opts

  @impl true
  def call(conn, _opts) do
    conn
    |> maybe_hsts()
    |> put_resp_header("permissions-policy", @permissions)
    |> maybe_noindex()
    |> register_before_send(&put_csp/1)
  end

  defp maybe_noindex(conn) do
    if Application.get_env(:claper, :allow_search_indexing, false),
      do: conn,
      else: put_resp_header(conn, "x-robots-tag", "noindex, nofollow")
  end

  defp maybe_hsts(conn) do
    if config()[:hsts], do: put_resp_header(conn, "strict-transport-security", @hsts), else: conn
  end

  # At send time, so a plug further in (ClaperWeb.Plugs.Iframe) has had its say
  # on framing, and a page may set its own policy.
  defp put_csp(conn) do
    if get_resp_header(conn, "content-security-policy") == [] do
      put_resp_header(conn, "content-security-policy", policy(frame_ancestors(conn)))
    else
      conn
    end
  end

  defp frame_ancestors(conn) do
    case get_resp_header(conn, "x-frame-options") do
      ["ALLOWALL" | _] -> "*"
      ["DENY" | _] -> "'none'"
      ["SAMEORIGIN" | _] -> "'self'"
      # LTI launches (no X-Frame-Options): opened inside the LMS
      _ -> nil
    end
  end

  @doc "The policy, with `frame_ancestors` (`nil` leaves framing unrestricted)."
  def policy(frame_ancestors) do
    [
      "default-src 'self'",
      "script-src 'self' #{ThemeScript.csp_hash()}",
      "style-src 'self' 'unsafe-inline'",
      "img-src 'self' data: blob: https:",
      "font-src 'self' data:",
      "connect-src 'self' #{socket_origin()}",
      "media-src 'self' data: blob: https:",
      "frame-src 'self' https: http:",
      "worker-src 'self' blob:",
      "object-src 'none'",
      "base-uri 'self'",
      "form-action 'self'#{logout_origin()}",
      frame_ancestors && "frame-ancestors #{frame_ancestors}",
      config()[:hsts] && "upgrade-insecure-requests"
    ]
    |> Enum.reject(&(&1 in [nil, false]))
    |> Enum.join("; ")
  end

  # LiveView's websocket on the app's own address ('self' covers it in
  # current browsers; named for older ones)
  defp socket_origin do
    uri = URI.parse(ClaperWeb.Endpoint.url())
    scheme = if uri.scheme == "https", do: "wss", else: "ws"
    port = if uri.port in [80, 443, nil], do: "", else: ":#{uri.port}"
    "#{scheme}://#{uri.host}#{port}"
  end

  # Signing out may end on another site (LOGOUT_REDIRECT_URL); browsers apply
  # form-action to where a submitted form redirects.
  defp logout_origin do
    with url when is_binary(url) <- Application.get_env(:claper, :logout_redirect_url),
         %URI{scheme: scheme, host: host} when scheme in ["http", "https"] and is_binary(host) <-
           URI.parse(url) do
      " #{scheme}://#{host}"
    else
      _ -> ""
    end
  end

  defp config, do: Application.get_env(:claper, ClaperWeb.Endpoint, [])
end
