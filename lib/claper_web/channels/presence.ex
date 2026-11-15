defmodule ClaperWeb.Presence do
  @moduledoc """
  Provides presence tracking to channels and processes.

  See the [`Phoenix.Presence`](http://hexdocs.pm/phoenix/Phoenix.Presence.html)
  docs for more details.
  """
  use Phoenix.Presence,
    otp_app: :claper,
    pubsub_server: Claper.PubSub

  @doc """
  How many phones are in an event right now. Each phone is counted once
  however many pages it has open (tracked by its attendee ticket).
  """
  def attendee_count(event_uuid), do: "event:#{event_uuid}" |> list() |> map_size()
end
