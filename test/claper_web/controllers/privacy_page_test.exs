defmodule ClaperWeb.PrivacyPageTest do
  @moduledoc "The privacy page states what this copy keeps, for how long, and who helps run it."
  use ClaperWeb.ConnCase, async: false

  alias Claper.Branding

  setup do
    keys = [:privacy_url, :remote_ip_headers, :record_retention_days, Claper.Mailer]
    previous = for key <- keys, do: {key, Application.get_env(:claper, key)}

    on_exit(fn ->
      for {key, value} <- previous, do: Application.put_env(:claper, key, value)
      Branding.clear_cache()
    end)

    :ok
  end

  defp page(conn), do: conn |> get(~p"/privacy") |> html_response(200)

  test "names the organization, the contact, and how long sign-in records are kept", %{conn: conn} do
    {:ok, _} =
      Branding.update(%{"name" => "Northside", "privacy_email" => "privacy@northside.example"})

    Application.put_env(:claper, :record_retention_days, 365)
    html = page(conn)

    assert html =~ "Northside runs this app"
    assert html =~ ~s(href="mailto:privacy@northside.example")
    assert html =~ "deleted automatically after 365 days"
    assert html =~ "no tracking"
  end

  test "lists only the services this copy is set up with", %{conn: conn} do
    Application.put_env(:claper, :remote_ip_headers, ["cf-connecting-ip"])
    Application.put_env(:claper, Claper.Mailer, adapter: Swoosh.Adapters.Resend)
    html = page(conn)
    assert html =~ "Cloudflare"
    assert html =~ "Resend"

    Application.put_env(:claper, :remote_ip_headers, ["x-forwarded-for"])
    Application.put_env(:claper, Claper.Mailer, adapter: Swoosh.Adapters.Local)
    html = page(conn)
    refute html =~ "Cloudflare"
    refute html =~ "Resend"
  end

  test "without a contact or a limit, it says so plainly", %{conn: conn} do
    Application.put_env(:claper, :record_retention_days, 0)
    html = page(conn)
    refute html =~ "mailto:"
    assert html =~ "kept until an administrator deletes them"
  end

  test "privacy links follow PRIVACY_URL when the organization has its own policy", %{conn: conn} do
    assert ClaperWeb.Privacy.url() == "/privacy"
    about = conn |> get(~p"/about") |> html_response(200)
    assert about =~ ~s(id="about-privacy" href="/privacy")

    Application.put_env(:claper, :privacy_url, "https://northside.example/privacy")
    assert ClaperWeb.Privacy.url() == "https://northside.example/privacy"
  end
end
