defmodule ClaperWeb.AuditContext do
  @moduledoc """
  Where an audited action came from (docs/SECURITY.md, "Audit Log"): the
  visitor's address (`ClaperWeb.ClientIp`) and, for page requests, the
  browser's user agent.

  Live pages can't see the address themselves (behind a proxy their
  connection is the proxy's), so the live sessions carry it from the page
  request (`live_session/1`) and `on_mount/4` puts it in `:client_ip`.
  """
  import Phoenix.Component, only: [assign: 3]

  @doc "From a page request."
  def from_conn(%Plug.Conn{} = conn) do
    %{
      ip_address: ClaperWeb.ClientIp.to_text(conn.remote_ip),
      user_agent: conn |> Plug.Conn.get_req_header("user-agent") |> List.first() |> truncate()
    }
  end

  @doc "From a live page."
  def from_socket(socket), do: %{ip_address: socket.assigns[:client_ip]}

  @doc """
  Records `action` by the signed-in person on a live page, with its address
  (`Claper.Audit.record/3` takes the same `opts`).
  """
  def record(socket, action, opts \\ []) do
    Claper.Audit.record(
      socket.assigns[:current_user],
      action,
      Keyword.put(opts, :context, from_socket(socket))
    )
  end

  @doc "Session data for live sessions whose pages audit actions."
  def live_session(conn), do: ClaperWeb.ClientIp.live_session(conn)

  @doc "Session data for the signed-in pages: the events list's view mode, and the address."
  def user_live_session(conn) do
    conn
    |> ClaperWeb.EventLive.Index.view_mode_session()
    |> Map.merge(live_session(conn))
  end

  def on_mount(:default, _params, session, socket) do
    {:cont, assign(socket, :client_ip, session["client_ip"])}
  end

  defp truncate(nil), do: nil
  defp truncate(text), do: String.slice(text, 0, 300)
end
