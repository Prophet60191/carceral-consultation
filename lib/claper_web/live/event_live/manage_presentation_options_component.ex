defmodule ClaperWeb.EventLive.ManagePresentationOptionsComponent do
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
          class="icon icon-tabler icons-tabler-outline icon-tabler-eye-cog shrink-0 text-base-content"
        >
          <path stroke="none" d="M0 0h24v24H0z" fill="none" />
          <path d="M10 12a2 2 0 1 0 4 0a2 2 0 0 0 -4 0" />
          <path d="M12 18c-3.6 0 -6.6 -2 -9 -6c2.4 -4 5.4 -6 9 -6c3.6 0 6.6 2 9 6" />
          <path d="M17.001 19a2 2 0 1 0 4 0a2 2 0 1 0 -4 0" />
          <path d="M19.001 15.5v1.5" />
          <path d="M19.001 21v1.5" />
          <path d="M22.032 17.25l-1.299 .75" />
          <path d="M17.27 20l-1.3 .75" />
          <path d="M15.97 17.25l1.3 .75" />
          <path d="M20.733 20l1.3 .75" />
        </svg>
        <span class="font-bold text-sm text-base-content">{gettext("Presentation Settings")}</span>
      </div>

      <div class="space-y-2 px-1">
        <ClaperWeb.Component.Switch.switch_row
          label={gettext("Show join instructions")}
          checked={@state.join_screen_visible}
          key={:join_screen_visible}
          shortcut={if @create == nil, do: "Q", else: nil}
          show_shortcut={@show_shortcut}
        />
        <ClaperWeb.Component.Switch.switch_row
          label={gettext("Show attendee count")}
          checked={@state.show_attendee_count}
          key={:show_attendee_count}
          shortcut={if @create == nil, do: "R", else: nil}
          show_shortcut={@show_shortcut}
        />
      </div>
    </div>
    """
  end
end
