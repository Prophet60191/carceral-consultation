defmodule ClaperWeb.AppHeader do
  @moduledoc """
  The header bar for the signed-in pages (My events, event stats, My account).
  (Carceral Consultation, 2026-11-13.)

  It lives inside each page rather than in the page layout, so its controls
  (search, the event tabs, grid/list) talk to the page, and it is redrawn
  correctly when you move between pages. Each page passes its own title and
  fills the `search` and `actions` slots with whatever it needs.

  The account button says "Admin" for administrators, otherwise the person's
  name. The bar stays pinned to the top while the page scrolls.
  """
  use Phoenix.Component
  use Gettext, backend: ClaperWeb.Gettext
  use Phoenix.VerifiedRoutes, endpoint: ClaperWeb.Endpoint, router: ClaperWeb.Router

  attr :user, :map, required: true
  attr :title, :string, required: true
  slot :search, doc: "desktop search box (optional)"
  slot :actions, doc: "desktop controls shown between the search and the account button"

  def header(assigns) do
    ~H"""
    <%!-- Phone: title and account button. Page controls sit in the page body. --%>
    <div class="lg:hidden app-bar sticky top-0 z-30 justify-between px-4">
      <h1 class="app-bar-title capitalize">{@title}</h1>
      <.account_menu user={@user} compact />
    </div>

    <%!-- Desktop: title, search, page controls, account button, in that order. --%>
    <div class="hidden lg:flex app-bar sticky top-0 z-30 px-6 xl:px-12">
      <h1 class="app-bar-title capitalize shrink-0">{@title}</h1>
      <div :if={@search != []} class="flex-1 min-w-0 max-w-md">
        {render_slot(@search)}
      </div>
      <div class="flex-1"></div>
      <div :if={@actions != []} class="flex items-center gap-2 shrink-0">
        {render_slot(@actions)}
      </div>
      <.account_menu user={@user} />
    </div>
    """
  end

  attr :user, :map, required: true
  attr :compact, :boolean, default: false

  attr :from, :string,
    default: nil,
    doc: "uuid of the event this menu is opened from; Admin and My account then lead back to it"

  @doc """
  The account button and its menu (My events, My account, Admin, Logout).
  Used by the header above and by the Manage screen's top bar.
  """
  def account_menu(assigns) do
    assigns = assign(assigns, :admin?, Claper.Accounts.user_has_role?(assigns.user, "admin"))

    ~H"""
    <div class="dropdown dropdown-end shrink-0">
      <div
        tabindex="0"
        role="button"
        aria-label={gettext("Account menu")}
        class={["btn btn-outline", if(@compact, do: "btn-circle btn-lg", else: "btn-lg")]}
      >
        <svg
          xmlns="http://www.w3.org/2000/svg"
          viewBox="0 0 24 24"
          fill="currentColor"
          class="size-4"
          aria-hidden="true"
        >
          <path
            fill-rule="evenodd"
            d="M7.5 6a4.5 4.5 0 1 1 9 0 4.5 4.5 0 0 1-9 0ZM3.751 20.105a8.25 8.25 0 0 1 16.498 0 .75.75 0 0 1-.437.695A18.683 18.683 0 0 1 12 22.5c-2.786 0-5.433-.608-7.812-1.7a.75.75 0 0 1-.437-.695Z"
            clip-rule="evenodd"
          />
        </svg>
        <span :if={!@compact}>
          {if @admin?, do: gettext("Admin"), else: Claper.Accounts.User.display_name(@user)}
        </span>
      </div>
      <div
        tabindex="0"
        class="dropdown-content z-50 mt-2 w-60 rounded-box border border-line bg-base-200 p-1 shadow-lg"
      >
        <ul class="menu w-full p-0">
          <li><a href={~p"/events"}>{gettext("My events")}</a></li>
          <li><a href={~p"/breakouts"}>{gettext("Breakout library")}</a></li>
          <li><a href={~p"/intros"}>{gettext("Intro library")}</a></li>
          <li><a href={with_from(~p"/users/settings", @from)}>{gettext("My account")}</a></li>
          <li :if={@admin?}><a href={with_from(~p"/admin", @from)}>{gettext("Admin")}</a></li>
          <li><a href={~p"/about"}>{gettext("About this app")}</a></li>
        </ul>
        <%!-- Theme switcher, above Logout --%>
        <div class="my-1 border-y border-line">
          <ClaperWeb.ThemeScript.switcher />
        </div>
        <ul class="menu w-full p-0">
          <li>
            <.link href={~p"/users/log_out"} method="delete" class="text-error">
              {gettext("Logout")}
            </.link>
          </li>
          <li class="menu-title pointer-events-none">
            <span class="text-xs text-muted">Version {Application.spec(:claper, :vsn)}</span>
          </li>
        </ul>
      </div>
    </div>
    """
  end

  # ?from=<event uuid> from an event; ?from=events otherwise (clears it)
  defp with_from(path, nil), do: path <> "?from=events"
  defp with_from(path, uuid), do: path <> "?from=" <> uuid
end
