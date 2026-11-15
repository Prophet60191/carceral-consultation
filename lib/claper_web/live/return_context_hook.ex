defmodule ClaperWeb.ReturnContextHook do
  @moduledoc """
  Assigns `:return_event` (or nil) on Admin and My account pages: the event
  you came from, if you may manage it. Read from the session that
  `ClaperWeb.Plugs.ReturnContext` keeps. Used by the breadcrumbs.
  """
  import Phoenix.Component, only: [assign: 3]

  def on_mount(:default, _params, session, socket) do
    socket = ClaperWeb.UserAuth.mount_current_user(socket, session)
    user = socket.assigns[:current_user]
    uuid = session[ClaperWeb.Plugs.ReturnContext.session_key()]

    event = if user, do: Claper.Events.get_return_event(user, uuid)
    {:cont, assign(socket, :return_event, event)}
  end
end
