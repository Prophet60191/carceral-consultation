defmodule ClaperWeb.LayoutView do
  import Phoenix.Component
  use ClaperWeb, :view

  # Phoenix LiveDashboard is available only in development by default,
  # so we instruct Elixir to not warn if the dashboard route is missing.
  @compile {:no_warn_undefined, {Routes, :live_dashboard_path, 2}}

  def active_class(conn, path) do
    current_path = Path.join(["/" | conn.path_info])

    if path == current_path do
      "bg-base-100 text-base-content"
    else
      ""
    end
  end

  def active_live_class(conn, path) do
    if path == conn.host_uri do
      "bg-base-100 text-base-content"
    else
      ""
    end
  end

  @doc "The organization's name, for page titles (the Brand page)."
  def brand_name, do: Claper.Branding.name(Claper.Branding.get())

  @doc "The browser tab icon (the Brand page's, or the default)."
  def brand_icon, do: Claper.Branding.icon_src(Claper.Branding.get())

  @doc """
  Returns the DaisyUI `active` class when `tab` is the current admin section.

  The current section is provided by `ClaperWeb.AdminLive.NavHook` as the
  `:active_tab` assign, which updates on every live navigation.
  """
  def admin_active(active_tab, tab) when active_tab == tab,
    do: "bg-base-300 text-base-content font-semibold"

  def admin_active(_active_tab, _tab), do: ""

  @doc "Breadcrumbs after the origin on Admin pages: Admin, then the section."
  def admin_crumbs(:dashboard), do: [{gettext("Admin"), nil}]
  def admin_crumbs(nil), do: [{gettext("Admin"), nil}]

  def admin_crumbs(tab) do
    [{gettext("Admin"), ~p"/admin"}, {admin_section_label(tab), nil}]
  end

  defp admin_section_label(:events), do: gettext("Events")
  defp admin_section_label(:users), do: gettext("Users")
  defp admin_section_label(:audit_logs), do: gettext("Audit Logs")
  defp admin_section_label(:oidc_providers), do: gettext("OIDC Providers")
  defp admin_section_label(:lti_platforms), do: gettext("LTI Platforms")
  defp admin_section_label(:brand), do: gettext("Brand")
  defp admin_section_label(:settings), do: gettext("Settings")

  def get_section_path(conn) do
    section = Enum.at(conn.path_info, 1)

    case section do
      "users" -> ~p"/admin/users"
      "events" -> ~p"/admin/events"
      "oidc_providers" -> ~p"/admin/oidc_providers"
      _ -> ~p"/admin"
    end
  end

  def active_link(%Plug.Conn{} = conn, text, opts) do
    class =
      [opts[:class], active_class(conn, opts[:to])]
      |> Enum.filter(& &1)
      |> Enum.join(" ")

    opts =
      opts
      |> Keyword.put(:class, class)

    link(text, opts)
  end

  def active_link(%Phoenix.LiveView.Socket{} = conn, text, opts) do
    class =
      [opts[:class], active_live_class(conn, opts[:to])]
      |> Enum.filter(& &1)
      |> Enum.join(" ")

    opts =
      opts
      |> Keyword.put(:class, class)

    link(text, opts)
  end
end
