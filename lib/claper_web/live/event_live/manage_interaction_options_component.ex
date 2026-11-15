defmodule ClaperWeb.EventLive.ManageInteractionOptionsComponent do
  @moduledoc false
  use Phoenix.Component
  use Gettext, backend: ClaperWeb.Gettext

  def render(assigns) do
    assigns = assigns |> assign_new(:show_shortcut, fn -> true end)

    ~H"""
    <div class="panel">
      <div class="panel-header">
        <svg
          xmlns="http://www.w3.org/2000/svg"
          width="24"
          height="24"
          viewBox="0 0 24 24"
          fill="none"
          stroke="currentColor"
          stroke-width="2"
          stroke-linecap="round"
          stroke-linejoin="round"
          class="icon icon-tabler icons-tabler-outline icon-tabler-pointer-cog shrink-0 text-base-content"
        >
          <path stroke="none" d="M0 0h24v24H0z" fill="none" />
          <path d="M15.774 13.218l-.996 -.996l3.113 -2.09a1.2 1.2 0 0 0 -.309 -2.228l-13.582 -3.904l3.904 13.563a1.2 1.2 0 0 0 2.228 .308l2.09 -3.093l.343 .343" />
          <path d="M17.001 19a2 2 0 1 0 4 0a2 2 0 1 0 -4 0" />
          <path d="M19.001 15.5v1.5" />
          <path d="M19.001 21v1.5" />
          <path d="M22.032 17.25l-1.299 .75" />
          <path d="M17.27 20l-1.3 .75" />
          <path d="M15.97 17.25l1.3 .75" />
          <path d="M20.733 20l1.3 .75" />
        </svg>
        <span class="font-bold text-sm text-base-content">
          {gettext("Current Interaction Settings")}
        </span>
      </div>

      <div class="space-y-2 px-1">
        <%= case @current_interaction do %>
          <% %Claper.Polls.Poll{} -> %>
            <.presentation_visibility state={@state} create={@create} show_shortcut={@show_shortcut} />
          <% %Claper.Quizzes.Quiz{} -> %>
            <div class="space-y-2">
              <ClaperWeb.Component.Switch.switch_row
                label={gettext("Show results on big screen")}
                checked={@current_interaction.show_results}
                key={:quiz_show_results}
                shortcut={if @create == nil, do: "Z", else: nil}
                show_shortcut={@show_shortcut}
              />

              <.action_row
                label={gettext("Review questions")}
                key={:review_quiz_questions}
                disabled={!@current_interaction.show_results}
              />

              <div class="grid grid-cols-2 gap-2">
                <.action_row
                  label={gettext("Previous")}
                  key={:prev_quiz_question}
                  disabled={!@current_interaction.show_results}
                  compact
                >
                  <:icon>
                    <svg
                      xmlns="http://www.w3.org/2000/svg"
                      viewBox="0 0 20 20"
                      fill="currentColor"
                      class="w-5 h-5"
                    >
                      <path
                        fill-rule="evenodd"
                        d="M11.78 5.22a.75.75 0 0 1 0 1.06L8.06 10l3.72 3.72a.75.75 0 1 1-1.06 1.06l-4.25-4.25a.75.75 0 0 1 0-1.06l4.25-4.25a.75.75 0 0 1 1.06 0Z"
                        clip-rule="evenodd"
                      />
                    </svg>
                  </:icon>
                </.action_row>

                <.action_row
                  label={gettext("Next")}
                  key={:next_quiz_question}
                  disabled={!@current_interaction.show_results}
                  compact
                  reverse
                >
                  <:icon>
                    <svg
                      xmlns="http://www.w3.org/2000/svg"
                      viewBox="0 0 20 20"
                      fill="currentColor"
                      class="w-5 h-5"
                    >
                      <path
                        fill-rule="evenodd"
                        d="M8.22 5.22a.75.75 0 0 1 1.06 0l4.25 4.25a.75.75 0 0 1 0 1.06l-4.25 4.25a.75.75 0 0 1-1.06-1.06L11.94 10 8.22 6.28a.75.75 0 0 1 0-1.06Z"
                        clip-rule="evenodd"
                      />
                    </svg>
                  </:icon>
                </.action_row>
              </div>
            </div>
          <% %Claper.WordClouds.WordCloud{} -> %>
            <div class="space-y-2">
              <ClaperWeb.Component.Switch.switch_row
                label={gettext("Show word cloud on phones")}
                checked={@current_interaction.show_results}
                key={:word_cloud_show_results}
              />

              <.presentation_visibility
                state={@state}
                create={@create}
                show_shortcut={@show_shortcut}
              />

              <.word_cloud_preview word_cloud={@current_interaction} words={@word_cloud_words} />
            </div>
          <% %Claper.Forms.Form{} -> %>
            <.presentation_visibility
              state={@state}
              create={@create}
              show_shortcut={@show_shortcut}
              label={gettext("Show answers on big screen")}
            />
          <% nil -> %>
            <p class="text-muted italic mt-1.5 text-sm">{gettext("No interaction enabled")}</p>
          <% _ -> %>
            <p class="text-muted italic mt-1.5 text-sm">
              {gettext("No settings available for this interaction")}
            </p>
        <% end %>
      </div>
    </div>
    """
  end

  attr :state, :map, required: true
  attr :create, :any, default: nil
  attr :show_shortcut, :boolean, default: true
  attr :label, :string, default: nil

  defp presentation_visibility(assigns) do
    ~H"""
    <ClaperWeb.Component.Switch.switch_row
      label={@label || gettext("Show results on big screen")}
      checked={@state.poll_visible}
      key={:poll_visible}
      shortcut={if @create == nil, do: "Z", else: nil}
      show_shortcut={@show_shortcut}
    />
    """
  end

  attr :word_cloud, Claper.WordClouds.WordCloud, required: true
  attr :words, :list, required: true

  defp word_cloud_preview(assigns) do
    ~H"""
    <div class="panel-inset p-3">
      <p class="mb-2 text-xs font-semibold text-muted">{gettext("Words")}</p>
      <p :if={@words == []} class="text-muted italic text-sm">{gettext("No words yet")}</p>
      <div :if={@words != []} class="flex flex-wrap items-baseline gap-x-3 gap-y-1">
        <button
          :for={word <- @words}
          type="button"
          phx-click="hide-word"
          phx-value-id={@word_cloud.id}
          phx-value-key={word.key}
          title={gettext("Hide this word")}
          class="btn btn-link btn-xs hover:line-through"
        >
          {word.text}<sup class="ml-0.5 text-xs font-normal text-muted">{word.count}</sup>
        </button>
      </div>

      <div :if={@word_cloud.hidden_words != []} class="mt-3">
        <p class="mb-1 text-xs font-semibold text-muted">{gettext("Hidden words")}</p>
        <div class="flex flex-wrap gap-1">
          <button
            :for={key <- @word_cloud.hidden_words}
            type="button"
            phx-click="unhide-word"
            phx-value-id={@word_cloud.id}
            phx-value-key={key}
            title={gettext("Show this word again")}
            class="btn btn-outline btn-xs text-muted line-through hover:no-underline"
          >
            {key}
          </button>
        </div>
      </div>
    </div>
    """
  end

  # A button row in the same style as the switch rows (switch-card): text,
  # no icon tile; Previous / Next keep a small arrow for the direction.
  attr :label, :string, required: true
  attr :key, :atom, required: true
  attr :disabled, :boolean, default: false
  attr :compact, :boolean, default: false
  attr :reverse, :boolean, default: false
  slot :icon

  defp action_row(assigns) do
    ~H"""
    <button
      phx-click={ClaperWeb.Component.Input.checked(false, @key)}
      phx-value-key={@key}
      type="button"
      disabled={@disabled}
      class={[
        "btn btn-outline w-full gap-2",
        if(@compact, do: "justify-center", else: "justify-start"),
        if(@reverse, do: "flex-row-reverse")
      ]}
    >
      <span :if={@icon != []} class="shrink-0 text-muted">{render_slot(@icon)}</span>
      <span>{@label}</span>
    </button>
    """
  end
end
