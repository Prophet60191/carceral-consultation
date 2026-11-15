defmodule ClaperWeb.ClientIpTest do
  @moduledoc "The visitor's address behind a proxy (docs/SECURITY.md)."
  use ExUnit.Case, async: false

  alias ClaperWeb.ClientIp

  @tunnel {172, 30, 0, 5}
  @stranger {203, 0, 113, 9}

  setup do
    proxies = Application.get_env(:claper, :remote_ip_proxies)
    headers = Application.get_env(:claper, :remote_ip_headers)

    on_exit(fn ->
      Application.put_env(:claper, :remote_ip_proxies, proxies)
      Application.put_env(:claper, :remote_ip_headers, headers)
    end)

    Application.put_env(:claper, :remote_ip_proxies, ["172.30.0.0/24"])
    Application.put_env(:claper, :remote_ip_headers, ["cf-connecting-ip"])
    :ok
  end

  test "a request through the trusted proxy gets the visitor's address" do
    assert ClientIp.resolve(@tunnel, [{"cf-connecting-ip", "198.51.100.7"}]) ==
             {198, 51, 100, 7}
  end

  test "anyone else's forwarding header is ignored" do
    assert ClientIp.resolve(@stranger, [{"cf-connecting-ip", "198.51.100.7"}]) == @stranger
  end

  test "headers other than the configured one are ignored, even from the proxy" do
    headers = [
      {"x-client-ip", "1.2.3.4"},
      {"x-real-ip", "1.2.3.5"},
      {"x-forwarded-for", "1.2.3.6"}
    ]

    assert ClientIp.resolve(@tunnel, headers) == @tunnel
  end

  test "with no proxies configured, no header is believed" do
    Application.put_env(:claper, :remote_ip_proxies, [])
    assert ClientIp.resolve(@tunnel, [{"cf-connecting-ip", "198.51.100.7"}]) == @tunnel
  end

  test "x-forwarded-for: the address the proxy added, not ones the visitor wrote" do
    Application.put_env(:claper, :remote_ip_headers, ["x-forwarded-for"])
    headers = [{"x-forwarded-for", "9.9.9.9, 198.51.100.7"}]
    assert ClientIp.resolve(@tunnel, headers) == {198, 51, 100, 7}
  end

  test "IPv6 proxies and single addresses are understood; bad entries are skipped" do
    Application.put_env(:claper, :remote_ip_proxies, ["not-an-ip", "fd00::/8", "10.1.2.3"])
    header = [{"cf-connecting-ip", "2001:db8::1"}]

    assert ClientIp.resolve({0xFD00, 0, 0, 0, 0, 0, 0, 1}, header) ==
             {0x2001, 0xDB8, 0, 0, 0, 0, 0, 1}

    assert ClientIp.resolve({10, 1, 2, 3}, header) == {0x2001, 0xDB8, 0, 0, 0, 0, 0, 1}
    assert ClientIp.resolve({10, 1, 2, 4}, header) == {10, 1, 2, 4}
  end

  test "the plug rewrites the connection's address" do
    conn =
      Plug.Test.conn(:get, "/")
      |> Map.put(:remote_ip, @tunnel)
      |> Plug.Conn.put_req_header("cf-connecting-ip", "198.51.100.7")
      |> ClientIp.call([])

    assert conn.remote_ip == {198, 51, 100, 7}
    assert ClientIp.live_session(conn) == %{"client_ip" => "198.51.100.7"}
  end
end
