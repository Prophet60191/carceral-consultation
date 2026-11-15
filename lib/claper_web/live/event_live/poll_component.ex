defmodule ClaperWeb.EventLive.PollComponent do
  use ClaperWeb, :live_component

  @impl true
  def render(assigns) do
    assigns = assign_new(assigns, :focus_mode, fn -> false end)

    ~H"""
    <div class="font-display">
      <div
        :if={!@focus_mode}
        id="collapsed-poll"
        class="mx-auto hidden w-max rounded-full bg-base-100 px-5 py-3 shadow-xl ring-1 ring-line"
      >
        <button
          type="button"
          class="pressable block h-full w-full"
          phx-click={toggle_poll()}
          phx-target={@myself}
        >
          <div class="flex items-center gap-2 text-base-content">
            <svg
              xmlns="http://www.w3.org/2000/svg"
              class="h-5 w-5 text-primary"
              fill="none"
              viewBox="0 0 24 24"
              stroke="currentColor"
              stroke-width="2"
            >
              <path
                stroke-linecap="round"
                stroke-linejoin="round"
                d="M16 8v8m-4-5v5m-4-2v2m-2 4h12a2 2 0 002-2V6a2 2 0 00-2-2H6a2 2 0 00-2 2v12a2 2 0 002 2z"
              />
            </svg>
            <span class="text-sm font-bold">{gettext("See current poll")}</span>
          </div>
        </button>
      </div>
      <div
        id="extended-poll"
        class={[
          "w-full rounded-2xl bg-base-100 p-4 text-base-content",
          @focus_mode && "shadow-none ring-0",
          !@focus_mode && "shadow-2xl ring-1 ring-line"
        ]}
      >
        <div class="relative pr-8">
          <button
            :if={!@focus_mode}
            id="poll-pane"
            type="button"
            aria-label={gettext("Close")}
            class="btn btn-ghost btn-circle btn-sm absolute -right-1 -top-1 text-muted"
            phx-click={toggle_poll()}
            phx-target={@myself}
          >
            <svg
              xmlns="http://www.w3.org/2000/svg"
              class="h-5 w-5"
              fill="none"
              viewBox="0 0 24 24"
              stroke="currentColor"
              stroke-width="2"
            >
              <path stroke-linecap="round" stroke-linejoin="round" d="M6 18L18 6M6 6l12 12" />
            </svg>
          </button>

          <p class="mb-1 text-xs font-semibold text-muted">{gettext("Current poll")}</p>
          <p class="mb-1 text-lg font-bold leading-snug text-base-content">{@poll.title}</p>
          <%= if @poll.multiple do %>
            <p class="mb-4 text-sm text-muted">{gettext("Select one or multiple options")}</p>
          <% else %>
            <p class="mb-4 text-sm text-muted">{gettext("Select one option")}</p>
          <% end %>
        </div>
        <div>
          <div id="poll-options" class="flex flex-col gap-2">
            <%= if (length @poll.poll_opts) > 0 do %>
              <%= for {opt, idx} <- Enum.with_index(@poll.poll_opts) do %>
                <%= if (length @current_poll_vote) > 0 do %>
                  <% voted = Enum.any?(@current_poll_vote, &(&1.poll_opt_id == opt.id)) %>
                  <div class={[
                    "choice relative shrink-0 overflow-hidden cursor-default",
                    voted && "choice-selected"
                  ]}>
                    <div
                      style={"width: #{if @show_results, do: opt.percentage, else: 0}%;"}
                      class={[
                        "absolute inset-y-0 left-0 rounded-lg bg-base-content/15 transition-all duration-700",
                        voted && "bg-base-content/25"
                      ]}
                    >
                    </div>
                    <div class="z-10 flex min-w-0 items-center gap-3 text-left">
                      <span class={[
                        "grid h-4 w-4 shrink-0 place-items-center border-2",
                        @poll.multiple && "rounded",
                        !@poll.multiple && "rounded-full",
                        voted && "border-primary",
                        !voted && "border-line-strong"
                      ]}>
                        <span
                          :if={voted}
                          class={[
                            "h-1.5 w-1.5 bg-primary",
                            @poll.multiple && "rounded-sm",
                            !@poll.multiple && "rounded-full"
                          ]}
                        >
                        </span>
                      </span>
                      <span class="min-w-0 flex-1 pr-2">{opt.content}</span>
                    </div>
                    <span
                      :if={@show_results}
                      class="z-10 shrink-0 text-xs font-bold text-base-content"
                    >
                      {opt.percentage}% ({opt.vote_count})
                    </span>
                  </div>
                <% else %>
                  <button
                    id={"poll-opt-#{idx}"}
                    phx-click="select-poll-opt"
                    phx-value-opt={idx}
                    aria-pressed={to_string(Enum.member?(@selected_poll_opt, "#{idx}"))}
                    class="choice relative shrink-0 overflow-hidden"
                  >
                    <div
                      style={"width: #{if @show_results, do: opt.percentage, else: 0}%;"}
                      class="absolute inset-y-0 left-0 rounded-lg bg-base-content/15 transition-all duration-700"
                    >
                    </div>
                    <div class="z-10 flex min-w-0 items-center gap-3 text-left">
                      <span class={[
                        "grid h-4 w-4 shrink-0 place-items-center border-2",
                        @poll.multiple && "rounded",
                        !@poll.multiple && "rounded-full",
                        Enum.member?(@selected_poll_opt, "#{idx}") && "border-primary",
                        !Enum.member?(@selected_poll_opt, "#{idx}") && "border-line-strong"
                      ]}>
                        <span
                          :if={Enum.member?(@selected_poll_opt, "#{idx}")}
                          class={[
                            "h-1.5 w-1.5 bg-primary",
                            @poll.multiple && "rounded-sm",
                            !@poll.multiple && "rounded-full"
                          ]}
                        >
                        </span>
                      </span>
                      <span class="min-w-0 flex-1 pr-2">{opt.content}</span>
                    </div>
                    <span
                      :if={@show_results}
                      class="z-10 shrink-0 text-xs font-bold text-base-content"
                    >
                      {opt.percentage}% ({opt.vote_count})
                    </span>
                  </button>
                <% end %>
              <% end %>
            <% end %>
          </div>

          <%= if (length @current_poll_vote) > 0 do %>
            <button
              type="button"
              disabled
              data-submitted
              class="btn btn-secondary btn-disabled mt-4 w-full"
            >
              <svg
                xmlns="http://www.w3.org/2000/svg"
                class="h-5 w-5"
                viewBox="0 0 24 24"
                fill="none"
                stroke="currentColor"
                stroke-width="2"
                stroke-linecap="round"
                stroke-linejoin="round"
                aria-hidden="true"
              >
                <path stroke="none" d="M0 0h24v24H0z" fill="none" />
                <path d="M5 12l5 5l10 -10" />
              </svg>
              {gettext("Voted")}
            </button>
          <% else %>
            <%= if (length @selected_poll_opt) == 0 do %>
              <button type="button" disabled class="btn btn-secondary btn-disabled mt-4 w-full">
                {gettext("Vote")}
              </button>
            <% else %>
              <button phx-click="vote" phx-disable-with="..." class="btn btn-primary mt-4 w-full">
                {gettext("Vote")}
              </button>
            <% end %>
          <% end %>
        </div>
      </div>
    </div>
    """
  end

  def toggle_poll(js \\ %JS{}) do
    js
    |> JS.toggle(
      out: "animate__animated animate__zoomOut",
      in: "animate__animated animate__zoomIn",
      to: "#collapsed-poll",
      time: 50
    )
    |> JS.toggle(
      out: "animate__animated animate__zoomOut",
      in: "animate__animated animate__zoomIn",
      to: "#extended-poll"
    )
  end
end
