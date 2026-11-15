defmodule ClaperWeb.Plugs.ReturnContext do
  @moduledoc """
  Remembers which event you left for Admin or My account, for the
  breadcrumbs that lead back to it. (Carceral Consultation, 2026-11-13.)

  - A link carrying `?from=<event uuid>` (the account menu on an event's
    Manage screen) stores that event in the session.
  - `?from=events`, or opening My events itself, clears it, so the trail
    leads back to My events instead.
  - Anything else leaves it as it is, so the trail survives moving around
    Admin, links inside tables, and refreshing the page.

  Only the event's id is stored; who may see it is checked when it is shown
  (`Claper.Events.get_return_event/2`).
  """
  import Plug.Conn

  @key "return_event_uuid"
  def session_key, do: @key

  def init(opts), do: opts

  def call(conn, _opts) do
    cond do
      conn.request_path == "/events" -> delete_session(conn, @key)
      conn.params["from"] == "events" -> delete_session(conn, @key)
      uuid?(conn.params["from"]) -> put_session(conn, @key, conn.params["from"])
      true -> conn
    end
  end

  defp uuid?(value) when is_binary(value), do: match?({:ok, _}, Ecto.UUID.cast(value))
  defp uuid?(_), do: false
end
