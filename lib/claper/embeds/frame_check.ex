defmodule Claper.Embeds.FrameCheck do
  @moduledoc """
  Asks a website whether it lets other sites show it in a frame
  (Carceral Consultation, 2026-11-13). Used by the web content form to warn,
  never to block, when a "Website" address will show up blank.

  A site refuses framing with either response header:

    * `Content-Security-Policy: frame-ancestors ...` (the modern rule; when
      present, browsers ignore the older header). Anything short of `*`
      (or a bare `http:` scheme, which covers every site) shuts us out:
      'self', 'none' or a list of the site's own addresses.
    * `X-Frame-Options: DENY` or `SAMEORIGIN` (the older rule).

  Only the headers are read: the request stops after the first chunk of the
  page. `Content-Security-Policy-Report-Only` is ignored, as browsers do.

  Returns `:embeddable`, `{:blocked, header}` or `:unknown` (the site could
  not be reached, or answered with an error).
  """

  @timeout 5_000

  @spec check(String.t()) :: :embeddable | {:blocked, String.t()} | :unknown
  def check(url) when is_binary(url) do
    case fetch_headers(url) do
      {:ok, status, headers} when status < 400 -> verdict(headers)
      _ -> :unknown
    end
  end

  def check(_url), do: :unknown

  defp fetch_headers(url) do
    Req.get(url,
      retry: false,
      max_redirects: 5,
      connect_options: [timeout: @timeout],
      receive_timeout: @timeout,
      headers: [{"user-agent", "Mozilla/5.0 (embed check)"}],
      into: fn {:data, _chunk}, acc -> {:halt, acc} end
    )
    |> case do
      {:ok, %Req.Response{status: status, headers: headers}} -> {:ok, status, headers}
      {:error, _} -> :error
    end
  rescue
    _ -> :error
  end

  @doc false
  # Public for tests. `headers` is Req's map of lowercase name => [values].
  def verdict(headers) do
    case frame_ancestors(Map.get(headers, "content-security-policy", [])) do
      nil -> x_frame_options(Map.get(headers, "x-frame-options", []))
      sources -> if open_to_all?(sources), do: :embeddable, else: {:blocked, "frame-ancestors"}
    end
  end

  # Every enforced policy applies; the first one with frame-ancestors that
  # refuses us is enough to block.
  defp frame_ancestors(policies) do
    found =
      for policy <- policies,
          directive <- String.split(policy, ";"),
          [name | sources] = String.split(String.trim(directive)),
          String.downcase(name) == "frame-ancestors",
          do: Enum.map(sources, &String.downcase/1)

    case found do
      [] -> nil
      lists -> Enum.find(lists, &(not open_to_all?(&1))) || hd(lists)
    end
  end

  defp open_to_all?(sources), do: "*" in sources or "http:" in sources

  defp x_frame_options(values) do
    blocked =
      values
      |> Enum.flat_map(&String.split(&1, ","))
      |> Enum.map(&(&1 |> String.trim() |> String.downcase()))
      |> Enum.any?(&(&1 in ["deny", "sameorigin"]))

    if blocked, do: {:blocked, "x-frame-options"}, else: :embeddable
  end
end
