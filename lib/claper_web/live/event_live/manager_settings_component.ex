defmodule ClaperWeb.EventLive.ManagerSettingsComponent do
  use ClaperWeb, :live_component

  def render(assigns) do
    assigns = assigns |> assign_new(:show_shortcut, fn -> true end)

    ~H"""
    <div class="flex flex-col gap-4 p-4">
      <ClaperWeb.EventLive.ManageInteractionOptionsComponent.render
        current_interaction={@current_interaction}
        word_cloud_words={@word_cloud_words}
        state={@state}
        create={@create}
        show_shortcut={@show_shortcut}
      />
      <ClaperWeb.EventLive.ManagePresentationOptionsComponent.render
        state={@state}
        create={@create}
        show_shortcut={@show_shortcut}
      />
      <ClaperWeb.EventLive.ManageMessagesOptionsComponent.render
        state={@state}
        create={@create}
        show_shortcut={@show_shortcut}
      />
      <%!-- Handouts and take-home PDFs (docs/MATERIALS.md) --%>
      <.live_component
        :if={assigns[:event]}
        id={"#{@id}-materials"}
        module={ClaperWeb.EventLive.MaterialsComponent}
        event_id={@event.id}
      />
    </div>
    """
  end
end
