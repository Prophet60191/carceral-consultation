defmodule ClaperWeb.Component.Combobox do
  @moduledoc """
  The "Add" combobox (Jose, 2026-11-16; shadcn/ui's Combobox): one button,
  one row, wherever several kinds of thing can be added (the manage
  screen's interactions, a breakout's material, the intro page's blocks).
  It opens a panel with a search box and the choices, filtered as you type;
  ↑ ↓ move, Enter picks, Escape closes; on touch screens you tap.

  Picking a choice does what its chip used to: open its window (`patch`),
  go to its page (`navigate`) or send an event (`click`, with `value`).

  The button and panel are drawn once and the page never redraws them
  (`phx-update="ignore"`), so a page that redraws often (the manage screen,
  on every message) can't close it or lose the search. When the choices
  change, the block gets a new id and is drawn afresh. `Combobox` hook:
  `assets/js/combobox.js`; look: `assets/css/combobox.css`.

      <Combobox.combobox id="add-block" label={gettext("Add")}>
        <:option label="Poll" description="…" patch={~p"/…"}>
          <svg>…</svg>
        </:option>
      </Combobox.combobox>
  """
  use Phoenix.Component
  use Gettext, backend: ClaperWeb.Gettext

  attr :id, :string, required: true
  attr :label, :string, default: nil, doc: "the button's text (default: Add)"
  attr :placeholder, :string, default: nil
  attr :class, :any, default: nil

  slot :option, required: true do
    attr :label, :string, required: true
    attr :description, :string
    attr :keywords, :string, doc: "other words it's found by"
    attr :group, :string, doc: "a heading over consecutive choices"
    attr :patch, :string
    attr :navigate, :string
    attr :click, :string, doc: "an event sent to the page"
    attr :value, :string, doc: "sent with click as phx-value-value"
    attr :disabled, :boolean
    attr :badge, :string
  end

  def combobox(assigns) do
    assigns =
      assigns
      |> assign(:label, assigns.label || gettext("Add"))
      |> assign(:placeholder, assigns.placeholder || gettext("Search"))
      # New id when the choices change: the never-redrawn block is replaced
      |> assign(:version, :erlang.phash2(Enum.map(assigns.option, &Map.drop(&1, [:inner_block]))))

    ~H"""
    <div id={@id} class={["combobox", @class]} phx-hook="Combobox">
      <div id={"#{@id}-#{@version}"} phx-update="ignore">
        <button
          type="button"
          data-combobox-trigger
          aria-haspopup="listbox"
          aria-expanded="false"
          aria-controls={"#{@id}-panel"}
          class="btn btn-outline combobox-trigger"
        >
          <svg class="size-4" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
            <path stroke-linecap="round" d="M12 5v14M5 12h14" />
          </svg>
          <span class="flex-1 text-left">{@label}</span>
          <svg
            class="size-4 text-muted"
            viewBox="0 0 24 24"
            fill="none"
            stroke="currentColor"
            stroke-width="2"
            aria-hidden="true"
          >
            <path stroke-linecap="round" stroke-linejoin="round" d="m7 15 5 5 5-5M7 9l5-5 5 5" />
          </svg>
        </button>

        <div id={"#{@id}-panel"} data-combobox-panel class="combobox-panel" hidden>
          <label class="input input-sm combobox-search">
            <svg
              class="size-4"
              viewBox="0 0 24 24"
              fill="none"
              stroke="currentColor"
              stroke-width="2"
              aria-hidden="true"
            >
              <path
                stroke-linecap="round"
                stroke-linejoin="round"
                d="M21 21l-6-6m2-5a7 7 0 11-14 0 7 7 0 0114 0z"
              />
            </svg>
            <input
              type="text"
              data-combobox-input
              role="combobox"
              aria-expanded="true"
              aria-autocomplete="list"
              aria-controls={"#{@id}-list"}
              aria-label={@placeholder}
              placeholder={@placeholder}
              autocomplete="off"
            />
          </label>

          <div id={"#{@id}-list"} role="listbox" aria-label={@label} class="combobox-list">
            <%= for {option, index} <- Enum.with_index(@option) do %>
              <p
                :if={
                  option[:group] &&
                    (index == 0 || Enum.at(@option, index - 1)[:group] != option[:group])
                }
                class="combobox-group"
                data-combobox-group={option[:group]}
              >
                {option[:group]}
              </p>
              <.option option={option} id={"#{@id}-option-#{index}"} />
            <% end %>
          </div>
          <p data-combobox-empty hidden class="combobox-empty">{gettext("Nothing matches.")}</p>
        </div>
      </div>
    </div>
    """
  end

  attr :option, :map, required: true
  attr :id, :string, required: true

  defp option(assigns) do
    assigns =
      assign(
        assigns,
        :search,
        Enum.join([assigns.option.label, assigns.option[:keywords] || ""], " ")
      )

    ~H"""
    <%= cond do %>
      <% @option[:disabled] -> %>
        <div
          id={@id}
          role="option"
          aria-disabled="true"
          data-combobox-option
          data-search={@search}
          data-group={@option[:group]}
          class="menu-item combobox-option"
        >
          <.option_body option={@option} />
        </div>
      <% @option[:patch] || @option[:navigate] -> %>
        <.link
          id={@id}
          role="option"
          patch={@option[:patch]}
          navigate={@option[:navigate]}
          data-combobox-option
          data-search={@search}
          data-group={@option[:group]}
          tabindex="-1"
          class="menu-item combobox-option"
        >
          <.option_body option={@option} />
        </.link>
      <% true -> %>
        <button
          id={@id}
          type="button"
          role="option"
          phx-click={@option[:click]}
          phx-value-value={@option[:value]}
          data-combobox-option
          data-search={@search}
          data-group={@option[:group]}
          tabindex="-1"
          class="menu-item combobox-option"
        >
          <.option_body option={@option} />
        </button>
    <% end %>
    """
  end

  attr :option, :map, required: true

  defp option_body(assigns) do
    ~H"""
    <span :if={@option[:inner_block]} class="combobox-option-icon">
      {render_slot(@option)}
    </span>
    <span class="flex min-w-0 flex-1 flex-col text-left">
      <span class="flex items-center gap-2 text-sm font-medium text-base-content">
        {@option.label}
        <span :if={@option[:badge]} class="badge badge-sm badge-soft badge-primary">
          {@option[:badge]}
        </span>
      </span>
      <span :if={@option[:description]} class="text-xs leading-snug text-muted">
        {@option[:description]}
      </span>
    </span>
    """
  end
end
