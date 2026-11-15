defmodule ClaperWeb.HomeScreen do
  @moduledoc """
  The `<head>` tags that let a phone save the app to its home screen with
  the brand's icon and a name that fits (2026-11-15). Used by every page
  layout (root, user, admin). The files are served by
  `ClaperWeb.HomeScreenController`; how the icon is made is in
  `Claper.Branding.HomeIcon`.

  The manifest is fetched with credentials so it also loads while the app
  sits behind a sign-in such as Cloudflare Access.
  """
  use Phoenix.Component

  alias Claper.Branding
  alias Claper.Branding.HomeIcon

  def tags(assigns) do
    brand = Branding.get()

    assigns =
      assign(assigns,
        version: HomeIcon.version(brand),
        short_name: Branding.short_name(brand)
      )

    ~H"""
    <link rel="apple-touch-icon" sizes="180x180" href={"/home-icon/180.png?v=#{@version}"} />
    <meta name="apple-mobile-web-app-title" content={@short_name} />
    <link rel="manifest" href={"/manifest.webmanifest?v=#{@version}"} crossorigin="use-credentials" />
    """
  end
end
