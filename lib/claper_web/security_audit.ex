defmodule ClaperWeb.SecurityAudit do
  @moduledoc "Collects trusted actor context without recording submitted content."
  alias Claper.Audit.Security

  def observe(socket, resource_type, resource_id, reason, threshold \\ 3) do
    assigns = socket.assigns
    event = assigns[:event]
    presentation_file = assigns[:presentation_file]

    Security.record(
      assigns[:current_user],
      "security.suspicious_submission",
      %{
        resource_type: resource_type,
        resource_id: resource_id,
        reason: reason,
        event_id:
          cond do
            is_map(event) -> event.id
            is_map(presentation_file) -> presentation_file.event_id
            true -> nil
          end,
        ip_address: assigns[:security_audit_ip],
        attendee_fingerprint: Security.fingerprint(assigns[:attendee_identifier])
      },
      threshold
    )
  end

  @doc """
  The visitor's address, as worked out for the page request
  (`ClaperWeb.ClientIp`, passed in the live session). The socket's own peer
  address would be the proxy's, behind a tunnel.
  """
  def client_ip(session), do: session["client_ip"]
end
