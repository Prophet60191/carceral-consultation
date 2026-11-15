defmodule ClaperWeb.Plugs.SecurityHeadersTest do
  @moduledoc "Security headers (docs/SECURITY.md)."
  use ClaperWeb.ConnCase, async: false

  defp csp(conn), do: conn |> get_resp_header("content-security-policy") |> List.first()

  test "pages get a policy that only runs the app's own scripts", %{conn: conn} do
    conn = get(conn, ~p"/users/log_in")
    policy = csp(conn)

    assert policy =~ "default-src 'self'"
    assert policy =~ "script-src 'self' #{ClaperWeb.ThemeScript.csp_hash()}"
    [script_src] = Regex.run(~r/script-src [^;]*/, policy)
    refute script_src =~ "unsafe"
    assert policy =~ "object-src 'none'"
    assert policy =~ "frame-ancestors 'self'"
    assert get_resp_header(conn, "permissions-policy") != []
  end

  test "the page has no inline script except the hashed theme script", %{conn: conn} do
    html = conn |> get(~p"/users/log_in") |> html_response(200)
    inline = Regex.scan(~r/<script(?![^>]*\bsrc=)[^>]*>/, html)
    assert length(inline) == 1
    refute html =~ ~r/\son[a-z]+="/
  end

  test "the theme script's hash matches the text sent to the browser", %{conn: conn} do
    html = conn |> get(~p"/users/log_in") |> html_response(200)
    [_, js] = Regex.run(~r/<script>(.*?)<\/script>/s, html)
    hash = "'sha256-" <> Base.encode64(:crypto.hash(:sha256, js)) <> "'"
    assert hash == ClaperWeb.ThemeScript.csp_hash()
  end

  test "the attendee page stays embeddable (LMS)", %{conn: conn} do
    presentation_file = Claper.PresentationsFixtures.presentation_file_fixture(%{}, [:event])

    Claper.PresentationsFixtures.presentation_state_fixture(%{
      presentation_file: presentation_file
    })

    conn = get(conn, ~p"/e/#{presentation_file.event.code}")
    assert csp(conn) =~ "frame-ancestors *"
  end

  describe "over https" do
    setup do
      previous = Application.get_env(:claper, ClaperWeb.Endpoint)
      config = previous |> Keyword.put(:hsts, true) |> Keyword.put(:secure_cookie, true)
      Application.put_env(:claper, ClaperWeb.Endpoint, config)
      on_exit(fn -> Application.put_env(:claper, ClaperWeb.Endpoint, previous) end)
    end

    test "HSTS tells browsers to always use https", %{conn: conn} do
      conn = get(conn, ~p"/users/log_in")

      assert get_resp_header(conn, "strict-transport-security") == [
               "max-age=31536000; includeSubDomains"
             ]

      assert csp(conn) =~ "upgrade-insecure-requests"
    end

    test "the remember-me cookie is HTTPS-only", %{conn: conn} do
      user = Claper.AccountsFixtures.user_fixture()

      conn =
        conn
        |> Map.replace!(:secret_key_base, ClaperWeb.Endpoint.config(:secret_key_base))
        |> init_test_session(%{})
        |> ClaperWeb.UserAuth.log_in_user(user, %{"remember_me" => "true"})

      assert %{secure: true, http_only: true} =
               conn.resp_cookies["_claper_web_user_remember_me"]
    end
  end

  test "search engines are asked not to index the app", %{conn: conn} do
    conn = get(conn, ~p"/users/log_in")
    assert get_resp_header(conn, "x-robots-tag") == ["noindex, nofollow"]
  end

  test "no HSTS over plain http", %{conn: conn} do
    conn = get(conn, ~p"/users/log_in")
    assert get_resp_header(conn, "strict-transport-security") == []
  end
end
