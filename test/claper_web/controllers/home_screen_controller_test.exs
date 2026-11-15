defmodule ClaperWeb.HomeScreenControllerTest do
  @moduledoc "Saving the app to a phone's home screen (ClaperWeb.HomeScreen)."
  use ClaperWeb.ConnCase, async: false

  alias Claper.Branding
  alias Claper.Branding.HomeIcon

  setup do
    previous = Application.get_env(:claper, :storage_dir)
    dir = Path.join(System.tmp_dir!(), "home-screen-test-#{System.unique_integer([:positive])}")
    Application.put_env(:claper, :storage_dir, dir)

    on_exit(fn ->
      Application.put_env(:claper, :storage_dir, previous)
      File.rm_rf(dir)
      Branding.clear_cache()
    end)

    {:ok, _} = Branding.update(%{"name" => "Northside Reentry Network", "monogram" => "NR"})
    :ok
  end

  defp imagemagick?, do: Enum.any?(~w(magick convert), &System.find_executable/1)

  test "every page names the icon, the home-screen name and the manifest", %{conn: conn} do
    # Its own address: the sign-in pages limit requests per address
    html =
      conn
      |> Map.put(:remote_ip, {198, 51, 100, 240})
      |> get(~p"/users/log_in")
      |> html_response(200)

    version = HomeIcon.version(Branding.get())

    assert html =~ ~s(rel="apple-touch-icon")
    assert html =~ "/home-icon/180.png?v=#{version}"
    assert html =~ ~s(<meta name="apple-mobile-web-app-title" content="NR">)
    assert html =~ ~s(rel="manifest")
    assert html =~ ~s(crossorigin="use-credentials")
  end

  test "the manifest describes the app with the brand's names and icons", %{conn: conn} do
    conn = get(conn, ~p"/manifest.webmanifest")
    assert response_content_type(conn, :json) =~ "application/manifest+json"
    manifest = Jason.decode!(conn.resp_body)

    assert manifest["name"] == "Northside Reentry Network"
    assert manifest["short_name"] == "NR"
    assert manifest["start_url"] == "/"
    assert Enum.map(manifest["icons"], & &1["sizes"]) == ["192x192", "512x512"]
    assert Enum.all?(manifest["icons"], &String.starts_with?(&1["src"], "/home-icon/"))
  end

  test "the icon is served at its sizes and at the addresses iPhones try", %{conn: conn} do
    for path <- [
          "/home-icon/180.png",
          "/home-icon/512.png",
          "/apple-touch-icon.png",
          "/apple-touch-icon-precomposed.png"
        ] do
      conn = get(conn, path)

      if imagemagick?() do
        assert conn.status == 200
        assert get_resp_header(conn, "content-type") == ["image/png"]
      else
        # Without ImageMagick: the browser icon as it is
        assert redirected_to(conn) == Branding.icon_src(Branding.get())
      end
    end
  end

  test "other sizes and names are not served", %{conn: conn} do
    for file <- ["64.png", "180.jpg", "..%2F..%2Fsecret.png", "1800.png"] do
      assert conn |> get("/home-icon/#{file}") |> response(404)
    end
  end
end
