defmodule ClaperWeb.IntroLive.Library do
  @moduledoc """
  The intro library (docs/INTRO.md, decision 4): intro pages saved for reuse,
  brought into any event from that event's intro builder. Reached from the
  account menu. Editing a library page never changes events that used it.
  """
  use ClaperWeb, :live_view

  on_mount(ClaperWeb.UserLiveAuth)

  alias Claper.Intro

  @impl true
  def mount(_params, session, socket) do
    with %{"locale" => locale} <- session do
      Gettext.put_locale(ClaperWeb.Gettext, locale)
    end

    {:ok, socket |> assign(page_title: gettext("Intro library"), name_error: nil) |> load()}
  end

  defp load(socket),
    do: assign(socket, :pages, Intro.list_library(socket.assigns.current_user.id))

  @impl true
  def handle_event("create", %{"title" => title}, socket) do
    case Intro.create_library_page(socket.assigns.current_user.id, title) do
      {:ok, page} -> {:noreply, push_navigate(socket, to: ~p"/intros/#{page.id}")}
      {:error, _} -> {:noreply, assign(socket, :name_error, gettext("Give it a name"))}
    end
  end

  def handle_event("delete", %{"id" => id}, socket) do
    case Intro.get_library_page(id, socket.assigns.current_user.id) do
      nil ->
        {:noreply, socket}

      page ->
        {:ok, _} = Intro.delete_library_page(page)
        {:noreply, socket |> put_flash(:info, gettext("Intro page deleted")) |> load()}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <ClaperWeb.AppHeader.header user={@current_user} title={gettext("Intro library")} />

    <div class="w-full px-4 pb-24 lg:px-6 xl:px-12">
      <div class="py-4">
        <ClaperWeb.Breadcrumbs.trail items={[
          {gettext("My events"), ~p"/events"},
          {gettext("Intro library"), nil}
        ]} />
      </div>

      <div class="flex flex-col gap-6">
        <section class="panel">
          <div class="panel-header gap-3">
            <ClaperWeb.BreakoutLive.Icons.plus class="size-5 text-muted" />
            <h2 class="text-base font-semibold text-base-content">{gettext("New intro page")}</h2>
          </div>
          <form id="intro-new" phx-submit="create" class="flex flex-col gap-2 p-3">
            <label class="flex flex-col gap-1">
              <span class="text-sm font-bold text-base-content">{gettext("Name")}</span>
              <div class="flex flex-wrap gap-2">
                <input
                  type="text"
                  name="title"
                  placeholder={gettext("e.g. Standard welcome")}
                  class="input min-w-0 flex-1"
                  maxlength="255"
                  autocomplete="off"
                  aria-invalid={@name_error && "true"}
                />
                <button type="submit" class="btn btn-primary">{gettext("Create")}</button>
              </div>
              <span :if={@name_error} class="text-sm text-error">{@name_error}</span>
            </label>
          </form>
        </section>

        <section class="panel">
          <div class="panel-header gap-3">
            <ClaperWeb.BreakoutLive.Icons.library class="size-5 text-muted" />
            <h2 class="text-base font-semibold text-base-content">{gettext("Your intro pages")}</h2>
          </div>
          <p :if={@pages == []} class="p-3 text-sm text-muted">
            {gettext(
              "Nothing saved yet. Build one here, or open an event's intro page and choose \"Save a copy\". Saved pages can be brought into any event."
            )}
          </p>
          <ul :if={@pages != []} class="flex flex-col divide-y divide-line">
            <li :for={page <- @pages} id={"intro-#{page.id}"} class="flex items-center gap-3 p-3">
              <div class="min-w-0 flex-1">
                <p class="truncate text-sm font-medium text-base-content">{page.title}</p>
                <p class="text-sm text-muted">
                  {ngettext("1 block", "%{count} blocks", length(page.blocks))}
                </p>
              </div>
              <.link navigate={~p"/intros/#{page.id}"} class="btn btn-outline btn-sm">
                {gettext("Edit")}
              </.link>
              <button
                type="button"
                class="btn btn-ghost btn-square btn-sm text-error"
                phx-click="delete"
                phx-value-id={page.id}
                data-confirm-title={gettext("Delete this intro page from your library?")}
                data-confirm={gettext("Events that already use it keep their copy.")}
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
    </div>
    """
  end
end
