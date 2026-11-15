defmodule Claper.Accounts.PwnedPasswords do
  @moduledoc """
  Has this password appeared in a known data breach? Asks Have I Been Pwned's
  Pwned Passwords service (docs/SECURITY.md).

  The password never leaves the app: only the first 5 characters of its
  SHA-1 hash are sent ("k-anonymity"). The service answers with every breached
  hash starting that way (hundreds), padded with decoys so the size of the
  answer gives nothing away, and the comparison happens here.

  Settings (`config :claper, Claper.Accounts.PwnedPasswords`):
  - `enabled` (`PASSWORD_BREACH_CHECK`, default true)
  - `req_options`: extra `Req` options (tests use a stub)

  If the service can't be reached the password is allowed (`:unknown`) and a
  warning is logged: an outage shouldn't stop people changing passwords.
  """
  require Logger

  @url "https://api.pwnedpasswords.com/range/"

  @spec check(String.t()) :: :breached | :not_found | :unknown | :disabled
  def check(password) when is_binary(password) do
    if config()[:enabled] == false do
      :disabled
    else
      hash = :crypto.hash(:sha, password) |> Base.encode16()
      {prefix, suffix} = String.split_at(hash, 5)

      case request(prefix) do
        {:ok, body} -> if listed?(body, suffix), do: :breached, else: :not_found
        {:error, reason} -> unknown(reason)
      end
    end
  end

  defp request(prefix) do
    options =
      [
        url: @url <> prefix,
        headers: [{"add-padding", "true"}, {"user-agent", "carceral-consultation-app"}],
        receive_timeout: 3_000,
        retry: false
      ] ++ (config()[:req_options] || [])

    case Req.get(options) do
      {:ok, %Req.Response{status: 200, body: body}} when is_binary(body) -> {:ok, body}
      {:ok, %Req.Response{status: status}} -> {:error, {:status, status}}
      {:error, error} -> {:error, error}
    end
  end

  # Lines are "SUFFIX:COUNT"; padding lines have a count of 0
  defp listed?(body, suffix) do
    body
    |> String.split(["\r\n", "\n"], trim: true)
    |> Enum.any?(fn line ->
      case String.split(line, ":") do
        [^suffix, count] -> String.trim(count) not in ["0", ""]
        _ -> false
      end
    end)
  end

  defp unknown(reason) do
    Logger.warning("Breached-password check unavailable: #{inspect(reason)}")
    :unknown
  end

  defp config, do: Application.get_env(:claper, __MODULE__, [])
end
