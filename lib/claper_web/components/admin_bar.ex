defmodule ClaperWeb.AdminBar do
  @moduledoc """
  The top bar of every Admin page (Carceral Consultation, 2026-11-13): the
  same 60px `.app-bar` as My events and Manage, with the page title, the
  page's own buttons (slot), the account button, the sidebar toggle on
  phones, and the breadcrumb trail under it.

  Each Admin page renders it first, in place of its own heading:

      <ClaperWeb.AdminBar.bar title={@page_title} user={@current_user}
        return_event={@return_event} active_tab={@active_tab}>
        <:actions>...</:actions>
      </ClaperWeb.AdminBar.bar>

  The page's buttons are drawn twice, in the bar (`data-actions="bar"`, from
  sm up) and in a row under it on phones (`data-actions="phone"`); tests
  click the bar copy.

  It reaches the edges of the content area with negative margins matching
  the Admin layout's padding (p-4, md:p-6).
  """
  use Phoenix.Component
  use Gettext, backend: ClaperWeb.Gettext

  attr :title, :string, required: true
  attr :user, :map, required: true
  attr :return_event, :any, default: nil
  attr :active_tab, :atom, default: nil
  slot :actions
  slot :tools, doc: "search and filters, on the breadcrumb line, right-aligned"

  def bar(assigns) do
    ~H"""
    <div class="app-bar -mx-4 -mt-4 px-4 md:-mx-6 md:-mt-6 md:px-6">
      <label
        for="drawer-toggle"
        class="btn btn-ghost btn-square lg:hidden"
        aria-label={gettext("Open menu")}
      >
        <svg fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2" aria-hidden="true">
          <path stroke-linecap="round" stroke-linejoin="round" d="M4 6h16M4 12h16M4 18h16" />
        </svg>
      </label>
      <h1 class="app-bar-title min-w-0 truncate">{@title}</h1>
      <div class="flex-1"></div>
      <div :if={@actions != []} data-actions="bar" class="hidden items-center gap-2 sm:flex">
        {render_slot(@actions)}
      </div>
      <span class="hidden lg:block">
        <ClaperWeb.AppHeader.account_menu user={@user} from={@return_event && @return_event.uuid} />
      </span>
      <span class="lg:hidden">
        <ClaperWeb.AppHeader.account_menu
          user={@user}
          from={@return_event && @return_event.uuid}
          compact
        />
      </span>
    </div>
    <%!-- Phones: the page's buttons get their own row under the bar --%>
    <div
      :if={@actions != []}
      data-actions="phone"
      class="-mx-4 flex flex-wrap items-center gap-2 bg-base-200 px-4 pb-3 sm:hidden"
    >
      {render_slot(@actions)}
    </div>
    <%!-- Breadcrumbs on the left; search and filters (if any) on the right --%>
    <div class="flex flex-wrap items-center justify-between gap-3 py-4">
      <ClaperWeb.Breadcrumbs.trail items={
        [ClaperWeb.Breadcrumbs.origin(@return_event)] ++
          ClaperWeb.LayoutView.admin_crumbs(@active_tab)
      } />
      <div :if={@tools != []} class="ml-auto flex flex-wrap items-center justify-end gap-2">
        {render_slot(@tools)}
      </div>
    </div>
    """
  end
end
