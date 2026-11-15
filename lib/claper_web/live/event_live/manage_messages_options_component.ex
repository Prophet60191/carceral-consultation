defmodule ClaperWeb.EventLive.ManageMessagesOptionsComponent do
  @moduledoc """
  Message Settings on the manage screen: every switch about messages in one
  panel (Jose, 2026-11-14): what phones can do with them, then what the big
  screen shows.
  """
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
          class="icon icon-tabler icons-tabler-outline icon-tabler-messages shrink-0 text-base-content"
        >
          <path stroke="none" d="M0 0h24v24H0z" fill="none" />
          <path d="M21 14l-3 -3h-7a1 1 0 0 1 -1 -1v-6a1 1 0 0 1 1 -1h9a1 1 0 0 1 1 1v10" />
          <path d="M14 15v2a1 1 0 0 1 -1 1h-7l-3 3v-10a1 1 0 0 1 1 -1h2" />
        </svg>
        <span class="font-bold text-sm text-base-content">{gettext("Message Settings")}</span>
      </div>

      <div class="space-y-2 px-1">
        <ClaperWeb.Component.Switch.switch_row
          label={gettext("Allow messages")}
          checked={@state.chat_enabled}
          key={:chat_enabled}
          shortcut={if @create == nil, do: "A", else: nil}
          show_shortcut={@show_shortcut}
        />
        <ClaperWeb.Component.Switch.switch_row
          label={gettext("Allow anonymous messages")}
          checked={@state.anonymous_chat_enabled}
          key={:anonymous_chat_enabled}
          shortcut={if @create == nil, do: "S", else: nil}
          disabled={!@state.chat_enabled}
          show_shortcut={@show_shortcut}
        />
        <ClaperWeb.Component.Switch.switch_row
          label={gettext("Allow reactions")}
          checked={@state.message_reaction_enabled}
          key={:message_reaction_enabled}
          shortcut={if @create == nil, do: "D", else: nil}
          show_shortcut={@show_shortcut}
        />
        <ClaperWeb.Component.Switch.switch_row
          label={gettext("Show messages on big screen")}
          checked={@state.chat_visible}
          key={:chat_visible}
          shortcut={if @create == nil, do: "W", else: nil}
          show_shortcut={@show_shortcut}
        />
        <ClaperWeb.Component.Switch.switch_row
          label={gettext("Show only pinned messages")}
          checked={@state.show_only_pinned}
          key={:show_only_pinned}
          shortcut={if @create == nil, do: "E", else: nil}
          disabled={!@state.chat_visible}
          show_shortcut={@show_shortcut}
        />
      </div>
    </div>
    """
  end
end
