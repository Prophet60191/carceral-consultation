defmodule ClaperWeb.PageController do
  use ClaperWeb, :controller

  def index(conn, _params) do
    conn
    |> render("index.html")
  end

  @doc "What this copy keeps and for how long (ClaperWeb.Privacy)."
  def privacy(conn, _params) do
    brand = Claper.Branding.get()

    conn
    |> assign(:page_title, gettext("Privacy"))
    |> render("privacy.html",
      name: Claper.Branding.name(brand),
      email: Claper.Branding.privacy_email(brand),
      retention_days: ClaperWeb.Privacy.retention_days(),
      services: ClaperWeb.Privacy.services()
    )
  end

  @doc """
  About this app: who runs this copy, that it is free software based on
  Claper, its license, the absence of warranty, and where to get its source
  code (AGPL-3.0 sections 5 and 13; docs/BRAND.md). Public: every person who
  uses the app can reach it.
  """
  def about(conn, _params) do
    brand = Claper.Branding.get()

    conn
    |> assign(:page_title, gettext("About"))
    |> render("about.html",
      name: Claper.Branding.name(brand),
      source_url: Claper.Branding.source_url(brand)
    )
  end
end
