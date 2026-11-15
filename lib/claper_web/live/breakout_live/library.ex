defmodule ClaperWeb.BreakoutLive.Library do
  @moduledoc """
  The breakout library (docs/BREAKOUT.md, decision 14): breakouts saved for
  reuse, built once and brought into any event. Reached from the account
  menu. Editing a library breakout never changes copies already in events.
  """
  use ClaperWeb, :live_view

  on_mount(ClaperWeb.UserLiveAuth)

  alias Claper.Breakouts

  @impl true
  def mount(_params, session, socket) do
    with %{"locale" => locale} <- session do
      Gettext.put_locale(ClaperWeb.Gettext, locale)
    end

    {:ok, socket |> assign(:page_title, gettext("Breakout library")) |> load()}
  end

  defp load(socket),
    do: assign(socket, :breakouts, Breakouts.list_library(socket.assigns.current_user.id))

  @impl true
  def handle_event("delete", %{"id" => id}, socket) do
    case Breakouts.get_library_breakout(id, socket.assigns.current_user.id) do
      nil ->
        {:noreply, socket}

      breakout ->
        {:ok, _} = Breakouts.delete_breakout(breakout)
        {:noreply, socket |> put_flash(:info, gettext("Breakout deleted")) |> load()}
    end
  end

  defp library_summary(b) do
    material =
      if b.material_mode == "per_case",
        do: gettext("Different material for each group"),
        else: gettext("Same material for every group")

    groups =
      if b.group_sizing == "group_count",
        do: gettext("%{n} groups", n: b.group_count),
        else: gettext("Groups of up to %{n}", n: b.max_group_size)

    material <> " · " <> groups
  end

  @impl true
  def render(assigns) do
    ~H"""
    <ClaperWeb.AppHeader.header user={@current_user} title={gettext("Breakout library")}>
      <:actions>
        <.link navigate={~p"/breakouts/new"} class="btn btn-primary btn-lg">
          <ClaperWeb.BreakoutLive.Icons.plus class="size-4" />
          {gettext("New breakout")}
        </.link>
      </:actions>
    </ClaperWeb.AppHeader.header>

    <div class="w-full px-4 pb-24 lg:px-6 xl:px-12">
      <div class="flex flex-wrap items-center justify-between gap-3 py-4">
        <ClaperWeb.Breadcrumbs.trail items={[
          {gettext("My events"), ~p"/events"},
          {gettext("Breakout library"), nil}
        ]} />
        <.link navigate={~p"/breakouts/new"} class="btn btn-primary lg:hidden">
          <ClaperWeb.BreakoutLive.Icons.plus class="size-4" />
          {gettext("New breakout")}
        </.link>
      </div>

      <section class="panel">
        <div class="panel-header gap-3">
          <ClaperWeb.BreakoutLive.Icons.library class="size-5 text-muted" />
          <h2 class="text-base font-semibold text-base-content">{gettext("Your breakouts")}</h2>
        </div>
        <p :if={@breakouts == []} class="p-3 text-sm text-muted">
          {gettext(
            "Nothing saved yet. Build a breakout here, or open one in an event and choose \"Save a copy to your library\". Saved breakouts can be brought into any event."
          )}
        </p>
        <ul :if={@breakouts != []} class="flex flex-col divide-y divide-line">
          <li :for={b <- @breakouts} id={"library-#{b.id}"} class="flex items-center gap-3 p-3">
            <div class="min-w-0 flex-1">
              <p class="truncate text-sm font-medium text-base-content">{b.title}</p>
              <p class="text-sm text-muted">
                {library_summary(b)}
              </p>
            </div>
            <.link navigate={~p"/breakouts/#{b.id}"} class="btn btn-outline btn-sm">
              {gettext("Edit")}
            </.link>
            <button
              type="button"
              class="btn btn-ghost btn-square btn-sm text-error"
              phx-click="delete"
              phx-value-id={b.id}
              data-confirm-title={gettext("Delete this breakout from your library?")}
              data-confirm={gettext("Copies already in events are kept.")}
              data-confirm-action={gettext("Delete")}
              data-confirm-variant="destructive"
              aria-label={gettext("Delete")}
            >
              <ClaperWeb.BreakoutLive.Icons.trash class="size-4" />
            </button>
          </li>
        </ul>
      </section>
    </div>
    """
  end
end
