defmodule ClaperWeb.Pagination do
  @moduledoc ~S"""
  The one pagination standard for every table (Carceral Consultation,
  2026-11-13), in the shadcn "data table" style: a footer under the table
  with "Showing 1–20 of 54" on the left and "Page 1 of 3" plus Previous /
  page numbers / Next on the right, in the segmented button-group look. It
  always shows, even on a single page (the buttons are then off).

  - Tables backed by Flop use `ClaperWeb.CoreComponents.pagination/1`, which
    renders this footer.
  - Tables that load a whole list use `paginate/3` to cut it into pages, and
    `footer/1` with a function that builds each page's link.

      <% pg = ClaperWeb.Pagination.paginate(@providers, @page) %>
      ... rows from pg.rows ...
      <ClaperWeb.Pagination.footer info={pg} path={fn n -> ~p"/admin/oidc_providers?page=#{n}" end} />
  """
  use Phoenix.Component
  use Gettext, backend: ClaperWeb.Gettext

  @per_page 20

  @doc "Read a page number from params (default 1)."
  def page_param(params, key \\ "page") do
    case Integer.parse(to_string(params[key] || "1")) do
      {n, _} when n > 0 -> n
      _ -> 1
    end
  end

  @doc "Cut a list into pages: %{rows, page, total_pages, total_count, page_size}."
  def paginate(list, page, per_page \\ @per_page) do
    total = length(list)
    total_pages = max(1, div(total + per_page - 1, per_page))
    page = page |> max(1) |> min(total_pages)

    %{
      rows: Enum.slice(list, (page - 1) * per_page, per_page),
      page: page,
      total_pages: total_pages,
      total_count: total,
      page_size: per_page
    }
  end

  attr :info, :map, required: true, doc: "%{page, total_pages, total_count, page_size}"
  attr :path, :any, required: true, doc: "fn page -> url"
  attr :class, :string, default: nil

  def footer(assigns) do
    i = assigns.info
    first = if i.total_count == 0, do: 0, else: (i.page - 1) * i.page_size + 1
    last = min(i.page * i.page_size, i.total_count)

    assigns =
      assign(assigns,
        first: first,
        last: last,
        items: page_items(i.page, i.total_pages)
      )

    ~H"""
    <nav
      aria-label={gettext("Pagination")}
      class={["flex flex-wrap items-center justify-between gap-3 py-3 text-sm text-muted", @class]}
    >
      <span :if={@info.total_count == 0}>{gettext("No results")}</span>
      <span :if={@info.total_count > 0}>
        {gettext("Showing %{first}–%{last} of %{total}",
          first: @first,
          last: @last,
          total: @info.total_count
        )}
      </span>
      <div class="flex items-center gap-3">
        <span>{gettext("Page %{page} of %{total}", page: @info.page, total: @info.total_pages)}</span>
        <div class={ClaperWeb.Component.Tabs.segmented_group_class()}>
          <.step to={@info.page > 1 && @path.(@info.page - 1)} label={gettext("Previous page")}>
            <svg class="size-4" viewBox="0 0 20 20" fill="currentColor" aria-hidden="true">
              <path
                fill-rule="evenodd"
                d="M12.79 5.23a.75.75 0 0 1-.02 1.06L8.832 10l3.938 3.71a.75.75 0 1 1-1.04 1.08l-4.5-4.25a.75.75 0 0 1 0-1.08l4.5-4.25a.75.75 0 0 1 1.06.02Z"
                clip-rule="evenodd"
              />
            </svg>
          </.step>
          <%= for item <- @items do %>
            <span :if={item == :gap} class="flex items-center px-2 text-faint" aria-hidden="true">
              …
            </span>
            <.link
              :if={item != :gap}
              patch={@path.(item)}
              aria-current={item == @info.page && "page"}
              class={[
                "flex items-center px-3 text-sm font-medium",
                ClaperWeb.Component.Tabs.segmented_item_class(item == @info.page)
              ]}
            >
              {item}
            </.link>
          <% end %>
          <.step
            to={@info.page < @info.total_pages && @path.(@info.page + 1)}
            label={gettext("Next page")}
          >
            <svg class="size-4" viewBox="0 0 20 20" fill="currentColor" aria-hidden="true">
              <path
                fill-rule="evenodd"
                d="M7.21 14.77a.75.75 0 0 1 .02-1.06L11.168 10 7.23 6.29a.75.75 0 1 1 1.04-1.08l4.5 4.25a.75.75 0 0 1 0 1.08l-4.5 4.25a.75.75 0 0 1-1.06-.02Z"
                clip-rule="evenodd"
              />
            </svg>
          </.step>
        </div>
      </div>
    </nav>
    """
  end

  attr :to, :any, required: true, doc: "url, or false when there is no such page"
  attr :label, :string, required: true
  slot :inner_block, required: true

  defp step(assigns) do
    ~H"""
    <.link
      :if={@to}
      patch={@to}
      aria-label={@label}
      class={["flex items-center px-2.5", ClaperWeb.Component.Tabs.segmented_item_class(false)]}
    >
      {render_slot(@inner_block)}
    </.link>
    <span
      :if={!@to}
      aria-label={@label}
      aria-disabled="true"
      class="flex items-center px-2.5 text-faint"
    >
      {render_slot(@inner_block)}
    </span>
    """
  end

  # Page numbers with gaps: 1 … 4 5 6 … 10
  defp page_items(_page, total) when total <= 7, do: Enum.to_list(1..total)

  defp page_items(page, total) do
    middle = Enum.to_list(max(2, page - 1)..min(total - 1, page + 1))
    left = if hd(middle) > 2, do: [1, :gap], else: [1]
    right = if List.last(middle) < total - 1, do: [:gap, total], else: [total]
    left ++ middle ++ right
  end
end
