defmodule ClaperWeb.EventLive.Handouts do
  @moduledoc """
  Handouts in the live room (docs/MATERIALS.md, Jose 2026-11-15): a page
  icon at the bottom right of every screen (the end of the bottom bar on
  phones and tablets), shown while at least one handout is switched on.
  With one handout it opens it; with several, a short list. The viewer
  covers the room, draws the PDF itself (`PdfViewer` hook) and has a
  download button; closing it returns to the slide.

  Open or closed is the server's (`ClaperWeb.EventLive.Show`: `handouts`,
  `handouts_menu`, `handout_open`), so LiveView's redraws never undo it.
  Placement is in `assets/css/room.css`.
  """
  use Phoenix.Component
  use Gettext, backend: ClaperWeb.Gettext

  use Phoenix.VerifiedRoutes,
    endpoint: ClaperWeb.Endpoint,
    router: ClaperWeb.Router,
    statics: ClaperWeb.static_paths()

  attr :handouts, :list, required: true
  attr :menu_open, :boolean, required: true

  @doc "The page icon and, with several handouts, their list."
  def button(assigns) do
    ~H"""
    <div :if={@handouts != []} id="room-handouts" class="room-handouts">
      <div
        :if={@menu_open and length(@handouts) > 1}
        id="room-handouts-menu"
        class="handouts-menu"
        role="menu"
        aria-labelledby="room-handouts-toggle"
        phx-click-away="close_handouts_menu"
        phx-window-keydown="close_handouts_menu"
        phx-key="Escape"
      >
        <p class="px-2 pb-1 text-xs font-bold uppercase tracking-wide text-muted">
          {gettext("Handouts")}
        </p>
        <button
          :for={handout <- @handouts}
          type="button"
          role="menuitem"
          phx-click="open_handout"
          phx-value-id={handout.uuid}
          class="menu-item w-full text-left"
        >
          <span class="truncate">{handout.title}</span>
        </button>
      </div>

      <button
        id="room-handouts-toggle"
        type="button"
        phx-click="toggle_handouts"
        aria-haspopup={if length(@handouts) > 1, do: "menu", else: "dialog"}
        aria-expanded={to_string(@menu_open)}
        aria-label={label(@handouts)}
        data-tooltip={label(@handouts)}
        data-tooltip-side="left"
        class="btn btn-secondary btn-circle btn-lg handouts-toggle"
      >
        <svg
          class="size-6"
          viewBox="0 0 24 24"
          fill="none"
          stroke="currentColor"
          stroke-width="1.8"
          stroke-linecap="round"
          stroke-linejoin="round"
          aria-hidden="true"
        >
          <path d="M14 3v4a1 1 0 0 0 1 1h4" />
          <path d="M17 21h-10a2 2 0 0 1 -2 -2v-14a2 2 0 0 1 2 -2h7l5 5v11a2 2 0 0 1 -2 2z" />
          <path d="M9 13h6" />
          <path d="M9 17h4" />
        </svg>
        <span :if={length(@handouts) > 1} class="handouts-count" aria-hidden="true">
          {length(@handouts)}
        </span>
      </button>
    </div>
    """
  end

  defp label([handout]), do: gettext("Handout: %{title}", title: handout.title)
  defp label(_), do: gettext("Handouts")

  attr :handout, :map, required: true

  @doc "The viewer: the handout over the room, with download and close."
  def viewer(assigns) do
    ~H"""
    <div
      id="handout-viewer"
      class="handout-viewer"
      role="dialog"
      aria-modal="true"
      aria-labelledby="handout-viewer-title"
    >
      <header class="handout-viewer-head">
        <h2 id="handout-viewer-title" class="min-w-0 flex-1 truncate text-base font-bold">
          {@handout.title}
        </h2>
        <a href={~p"/materials/#{@handout.uuid}?download=1"} download class="btn btn-primary btn-sm">
          <svg class="size-4" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
            <path stroke-linecap="round" stroke-linejoin="round" d="M12 4v12m0 0-4-4m4 4 4-4M5 20h14" />
          </svg>
          {gettext("Download")}
        </a>
        <button
          type="button"
          data-pdf-close
          phx-click="close_handout"
          aria-label={gettext("Close")}
          data-tooltip={gettext("Close")}
          class="btn btn-ghost btn-circle"
        >
          <svg class="size-5" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
            <path stroke-linecap="round" stroke-linejoin="round" d="M6 18 18 6M6 6l12 12" />
          </svg>
        </button>
      </header>

      <%!-- Drawn by the PdfViewer hook; the page never redraws inside it --%>
      <div
        id={"handout-pdf-#{@handout.uuid}"}
        class="handout-viewer-body"
        phx-hook="PdfViewer"
        phx-update="ignore"
        data-src={~p"/materials/#{@handout.uuid}"}
        data-page-label={gettext("Page")}
      >
        <p data-pdf-status class="py-10 text-center text-sm text-muted">
          {gettext("Opening the handout...")}
        </p>
        <div data-pdf-failed hidden class="flex flex-col items-center gap-3 py-10 text-center">
          <p class="text-sm text-base-content">{gettext("This handout can't be shown here.")}</p>
          <a href={~p"/materials/#{@handout.uuid}?download=1"} download class="btn btn-primary btn-sm">
            {gettext("Download it instead")}
          </a>
        </div>
        <div data-pdf-pages class="handout-pages"></div>
      </div>
    </div>
    """
  end
end
