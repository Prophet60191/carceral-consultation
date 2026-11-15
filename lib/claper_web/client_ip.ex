defmodule ClaperWeb.ClientIp do
  @moduledoc """
  The visitor's real address, when the app sits behind a proxy such as a
  Cloudflare Tunnel (docs/SECURITY.md).

  A forwarding header (`CF-Connecting-IP`, `X-Forwarded-For`, ...) is only
  believed when the request comes straight from a trusted proxy
  (`REMOTE_IP_PROXIES`). Anyone else could write any address into one, so
  for every other request the connection's own address is used. This is the
  rule nginx (`set_real_ip_from`) and Rails (trusted proxies) follow.

  Without it, the sign-in limit (10 tries a minute per address) could be
  dodged by sending a new made-up address with every guess, and the Audit Log
  would record whatever the visitor claimed.

  Settings (config/runtime.exs):

  - `REMOTE_IP_PROXIES`: comma-separated addresses or ranges (CIDR) of the
    proxies that connect to the app. Empty (the default): no header is
    believed.
  - `REMOTE_IP_HEADERS`: which header holds the visitor's address, by
    default `x-forwarded-for`. Behind Cloudflare use `cf-connecting-ip`.
  """
  @behaviour Plug

  import Bitwise
  require Logger

  @impl true
  def init(opts), do: opts

  @impl true
  def call(conn, _opts) do
    ip = resolve(conn.remote_ip, conn.req_headers)

    case :inet.ntoa(ip) do
      {:error, _} -> :ok
      text -> Logger.metadata(remote_ip: to_string(text))
    end

    %{conn | remote_ip: ip}
  end

  @doc """
  The visitor's address for a connection from `peer` carrying `headers`.
  Returns `peer` unless `peer` is a trusted proxy and the configured header
  holds an address.
  """
  @spec resolve(:inet.ip_address(), [{String.t(), String.t()}]) :: :inet.ip_address()
  def resolve(peer, headers) do
    proxies = proxies()

    if proxies != [] and in_any?(peer, proxies) do
      RemoteIp.from(headers, headers: header_names(), proxies: proxy_strings()) || peer
    else
      peer
    end
  end

  @doc """
  The address as text, for a LiveView session: LiveView's own connection
  info only carries the proxy's address, so the address worked out for the
  page request is handed over in the (signed) session.
  """
  def live_session(conn), do: %{"client_ip" => to_text(conn.remote_ip)}

  def to_text(ip) do
    case :inet.ntoa(ip) do
      {:error, _} -> nil
      text -> to_string(text)
    end
  end

  defp header_names do
    Application.get_env(:claper, :remote_ip_headers, ["x-forwarded-for"])
  end

  # Only entries that parse: one mistyped entry must not break every request
  defp proxy_strings do
    Application.get_env(:claper, :remote_ip_proxies, [])
    |> Enum.filter(&(parse_block(&1) != []))
  end

  defp proxies, do: Enum.flat_map(proxy_strings(), &parse_block/1)

  # "172.18.0.0/16", "10.0.0.5" or "fd00::/8" -> [{size, value, mask}]
  @doc false
  def parse_block(text) do
    {address, bits} =
      case String.split(String.trim(text), "/", parts: 2) do
        [address, bits] -> {address, Integer.parse(bits)}
        [address] -> {address, :all}
      end

    with {:ok, ip} <- :inet.parse_address(String.to_charlist(address)),
         {size, value} = to_integer(ip),
         {:ok, bits} <- prefix(bits, size) do
      mask = (1 <<< size) - (1 <<< (size - bits))
      [{size, value &&& mask, mask}]
    else
      _ -> []
    end
  end

  defp prefix(:all, size), do: {:ok, size}
  defp prefix({bits, ""}, size) when bits >= 0 and bits <= size, do: {:ok, bits}
  defp prefix(_, _), do: :error

  defp in_any?(ip, blocks) do
    {size, value} = to_integer(ip)
    Enum.any?(blocks, fn {s, net, mask} -> s == size and (value &&& mask) == net end)
  end

  defp to_integer({a, b, c, d}), do: {32, a <<< 24 ||| b <<< 16 ||| c <<< 8 ||| d}

  defp to_integer({_, _, _, _, _, _, _, _} = ip) do
    {128, ip |> Tuple.to_list() |> Enum.reduce(0, fn part, acc -> acc <<< 16 ||| part end)}
  end
end
