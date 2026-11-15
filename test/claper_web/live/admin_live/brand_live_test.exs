defmodule ClaperWeb.AdminLive.BrandLiveTest do
  @moduledoc """
  Admin › Brand and where the brand shows (docs/BRAND.md): the app's name,
  images and source code link come from settings, not code.
  """
  use ClaperWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Claper.AccountsFixtures

  alias Claper.{Accounts, Branding}

  @fixtures Path.expand("../../../support/fixtures/brand", __DIR__)

  setup do
    previous = Application.get_env(:claper, :storage_dir)
    dir = Path.join(System.tmp_dir!(), "brand-live-#{System.unique_integer([:positive])}")
    Application.put_env(:claper, :storage_dir, dir)

    on_exit(fn ->
      Application.put_env(:claper, :storage_dir, previous)
      File.rm_rf(dir)
      Branding.clear_cache()
    end)

    for name <- ["user", "admin"] do
      _ = Accounts.get_role_by_name(name) || elem(Accounts.create_role(%{name: name}), 1)
    end

    :ok
  end

  defp admin_conn(conn) do
    {:ok, admin} = Accounts.assign_role(confirmed_user_fixture(), "admin")
    {log_in_user(conn, admin), admin}
  end

  test "regular users cannot open the Brand page", %{conn: conn} do
    user = confirmed_user_fixture()
    assert {:error, {:redirect, _}} = conn |> log_in_user(user) |> live(~p"/admin/brand")
  end

  test "an administrator names the organization and the whole app follows", %{conn: conn} do
    {conn, _admin} = admin_conn(conn)
    {:ok, view, html} = live(conn, ~p"/admin/brand")
    assert html =~ "Your organization"

    view
    |> form("#brand-identity-form",
      brand: %{
        name: "Northside Reentry Network",
        monogram: "",
        description: "Workshops by people who came home."
      }
    )
    |> render_submit()

    assert Branding.name(Branding.get()) == "Northside Reentry Network"

    # The join page, the sign-in page and page titles
    {:ok, _join, join_html} = live(build_conn(), ~p"/")
    assert join_html =~ "Northside Reentry Network"
    assert join_html =~ "<title"
    assert join_html =~ "Northside Reentry Network</title>"

    signin = build_conn() |> get(~p"/users/log_in") |> html_response(200)
    assert signin =~ "Workshops by people who came home."
    assert signin =~ ~s(aria-label="Northside Reentry Network")
    refute signin =~ "Carceral"
  end

  test "an administrator sets the privacy contact; a wrong address is refused", %{conn: conn} do
    {conn, _admin} = admin_conn(conn)
    {:ok, view, _html} = live(conn, ~p"/admin/brand")

    html =
      view
      |> form("#brand-privacy-form", brand: %{privacy_email: "not an address"})
      |> render_submit()

    assert html =~ "Enter an email address"
    assert Branding.privacy_email(Branding.get()) == nil

    view
    |> form("#brand-privacy-form", brand: %{privacy_email: "privacy@northside.example"})
    |> render_submit()

    assert Branding.privacy_email(Branding.get()) == "privacy@northside.example"
  end

  test "an administrator sets the name under the home-screen icon", %{conn: conn} do
    {conn, _admin} = admin_conn(conn)
    {:ok, view, html} = live(conn, ~p"/admin/brand")
    assert html =~ "Home-screen name"
    assert has_element?(view, "#brand-home-icon-preview")

    view
    |> form("#brand-identity-form", brand: %{short_name: "Northside"})
    |> render_submit()

    assert Branding.short_name(Branding.get()) == "Northside"

    page =
      build_conn()
      |> Map.put(:remote_ip, {198, 51, 100, 241})
      |> get(~p"/users/log_in")
      |> html_response(200)

    assert page =~ ~s(<meta name="apple-mobile-web-app-title" content="Northside">)
  end

  test "the text form shows what doesn't fit", %{conn: conn} do
    {conn, _admin} = admin_conn(conn)
    {:ok, view, _} = live(conn, ~p"/admin/brand")

    html =
      view
      |> form("#brand-source-form", brand: %{source_url: "not a web address"})
      |> render_submit()

    assert html =~ "Enter a full web address"
    assert Branding.source_url(Branding.get()) == Branding.default_source_url()
  end

  test "a logo uploads, shows everywhere, and can be removed", %{conn: conn} do
    {conn, _admin} = admin_conn(conn)
    {:ok, view, _} = live(conn, ~p"/admin/brand")

    logo =
      file_input(view, "#brand-logo-form", :logo, [
        %{
          name: "logo.png",
          content: File.read!(Path.join(@fixtures, "logo.png")),
          type: "image/png"
        }
      ])

    render_upload(logo, "logo.png")
    src = Branding.get().logo_src
    assert "/uploads/brand/" <> _ = src
    assert render(view) =~ src

    {:ok, _join, join_html} = live(build_conn(), ~p"/")
    assert join_html =~ "--wm-src: url(&#39;#{src}&#39;)"

    view |> element("#brand-logo button", "Remove") |> render_click()
    assert Branding.get().logo_src == nil
  end

  test "a file that isn't really an image is refused with a reason", %{conn: conn} do
    {conn, _admin} = admin_conn(conn)
    {:ok, view, _} = live(conn, ~p"/admin/brand")

    fake =
      file_input(view, "#brand-logo-form", :logo, [
        %{
          name: "logo.png",
          content: File.read!(Path.join(@fixtures, "fake.png")),
          type: "image/png"
        }
      ])

    render_upload(fake, "logo.png")
    assert render(view) =~ "isn&#39;t a real image"
    assert Branding.get().logo_src == nil
  end

  test "an administrator demoted while the page is open can no longer change the brand",
       %{conn: conn} do
    {conn, admin} = admin_conn(conn)
    {:ok, view, _} = live(conn, ~p"/admin/brand")
    {:ok, _} = Accounts.assign_role(admin, "user")

    view |> form("#brand-identity-form", brand: %{name: "Hijacked"}) |> render_submit()
    refute Branding.name(Branding.get()) == "Hijacked"
  end

  describe "About page (AGPL-3.0)" do
    test "is open to everyone, credits Claper, and links to the source code", %{conn: conn} do
      {:ok, _} =
        Branding.update(%{"name" => "Northside", "source_url" => "https://example.org/src"})

      html = conn |> get(~p"/about") |> html_response(200)
      assert html =~ "Northside uses this app"
      assert html =~ "https://github.com/ClaperCo/Claper"
      assert html =~ "GNU Affero General Public License"
      assert html =~ "NO WARRANTY"
      assert html =~ ~s(id="about-source" href="https://example.org/src")
    end

    test "is linked from the join page and the sign-in page", %{conn: conn} do
      {:ok, _join, join_html} = live(conn, ~p"/")
      assert join_html =~ ~s(href="/about")

      signin = build_conn() |> get(~p"/users/log_in") |> html_response(200)
      assert signin =~ ~s(href="/about")
    end
  end
end
