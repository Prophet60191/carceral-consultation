defmodule ClaperWeb.Breadcrumbs do
  @moduledoc """
  Breadcrumb trail, and the "smart" start of it: the event you came from
  (back to its Manage screen) or My events. (Carceral Consultation, 2026-11-13.)

      <ClaperWeb.Breadcrumbs.trail items={[{"My events", ~p"/events"}, {"Admin", nil}]} />

  The last item is the current page (not a link).
  """
  use Phoenix.Component
  use Gettext, backend: ClaperWeb.Gettext
  use Phoenix.VerifiedRoutes, endpoint: ClaperWeb.Endpoint, router: ClaperWeb.Router

  attr :items, :list, required: true, doc: "[{label, href | nil}, ...]"
  attr :class, :string, default: nil

  def trail(assigns) do
    assigns = assign(assigns, :last, length(assigns.items) - 1)

    ~H"""
    <nav aria-label={gettext("Breadcrumb")} class={["min-w-0", @class]}>
      <ol class="flex flex-wrap items-center gap-1.5 text-sm text-muted">
        <%= for {{label, href}, i} <- Enum.with_index(@items) do %>
          <li class="flex items-center gap-1.5 min-w-0">
            <%= if i == @last or is_nil(href) do %>
              <span class="truncate text-base-content font-medium" aria-current={i == @last && "page"}>
                {label}
              </span>
            <% else %>
              <.link
                href={href}
                class="truncate hover:text-base-content hover:underline underline-offset-4"
              >
                {label}
              </.link>
            <% end %>
          </li>
          <li :if={i < @last} aria-hidden="true" class="text-faint">›</li>
        <% end %>
      </ol>
    </nav>
    """
  end

  @doc "The first crumb: the event you came from, or My events."
  def origin(nil), do: {gettext("My events"), ~p"/events"}

  def origin(event),
    do: {"#{event.name} (##{String.upcase(event.code)})", ~p"/e/#{event.code}/manage"}
end
