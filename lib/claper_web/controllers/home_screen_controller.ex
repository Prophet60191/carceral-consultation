defmodule ClaperWeb.HomeScreenController do
  @moduledoc """
  What a phone needs to put the app on its home screen (2026-11-15): the
  icon (`Claper.Branding.HomeIcon`) and the web app manifest. The tags that
  point to them are `ClaperWeb.HomeScreen.tags/1`.

  `/apple-touch-icon.png` and `/apple-touch-icon-precomposed.png` are where
  iPhones look by convention when a page names no icon, so they answer too.
  """
  use ClaperWeb, :controller

  alias Claper.Branding
  alias Claper.Branding.HomeIcon

  @doc "The 180-pixel icon at the fixed addresses iPhones try."
  def apple_touch_icon(conn, _params), do: send_icon(conn, 180, "public, max-age=86400")

  @doc "`/home-icon/:file`, where file is `180.png`, `192.png` or `512.png`."
  def icon(conn, %{"file" => file}) do
    with [digits] <- Regex.run(~r/\A(\d{3})\.png\z/, file, capture: :all_but_first),
         size when size in [180, 192, 512] <- String.to_integer(digits) do
      # Links carry ?v=<version>, so a brand change is a new address.
      send_icon(conn, size, "public, max-age=604800")
    else
      _ -> send_resp(conn, 404, "")
    end
  end

  @doc "The web app manifest (name, short name, colors, icons)."
  def manifest(conn, _params) do
    brand = Branding.get()
    version = HomeIcon.version(brand)
    page = ClaperWeb.Theme.email(:page)

    body = %{
      name: Branding.name(brand),
      short_name: Branding.short_name(brand),
      start_url: "/",
      scope: "/",
      display: "browser",
      background_color: page,
      theme_color: page,
      icons:
        for size <- [192, 512] do
          %{
            src: "/home-icon/#{size}.png?v=#{version}",
            sizes: "#{size}x#{size}",
            type: "image/png",
            purpose: "any"
          }
        end
    }

    conn
    |> put_resp_content_type("application/manifest+json")
    |> put_resp_header("cache-control", "public, max-age=3600")
    |> send_resp(200, Jason.encode!(body))
  end

  defp send_icon(conn, size, cache) do
    brand = Branding.get()

    case HomeIcon.path(brand, size) do
      {:ok, file} ->
        conn
        |> put_resp_content_type("image/png", nil)
        |> put_resp_header("cache-control", cache)
        |> send_file(200, file)

      # No ImageMagick here: the browser icon as it is beats nothing.
      {:error, _} ->
        redirect(conn, to: Branding.icon_src(brand))
    end
  end
end
