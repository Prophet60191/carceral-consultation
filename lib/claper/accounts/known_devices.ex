defmodule Claper.Accounts.KnownDevices do
  @moduledoc """
  Has this account signed in from this browser before? (docs/SECURITY.md,
  "New-device email".)

  Each browser keeps a random ID in a long-lived cookie (`ClaperWeb.UserAuth`);
  each account remembers the hashes of the IDs it has signed in from.

  - `:known`: seen before; its "last seen" is updated.
  - `:new`: a browser this account hasn't used: the owner is emailed.
  - `:first`: the account had no browsers on record (a new account, or one
    from before this existed). Recorded quietly.
  """
  import Ecto.Query

  alias Claper.Accounts.{User, UserDevice}
  alias Claper.Repo

  @spec seen(User.t(), String.t(), map()) :: :known | :new | :first
  def seen(%User{id: user_id}, device_id, attrs) when is_binary(device_id) do
    hash = hash(device_id)
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    details = [
      user_agent: truncate(attrs[:user_agent]),
      ip_address: attrs[:ip_address],
      last_seen_at: now
    ]

    Repo.transaction(fn ->
      existing = Repo.get_by(UserDevice, user_id: user_id, device_hash: hash)
      any? = Repo.exists?(from d in UserDevice, where: d.user_id == ^user_id)

      if existing do
        existing |> Ecto.Changeset.change(details) |> Repo.update!()
        :known
      else
        Repo.insert!(
          struct(UserDevice, [user_id: user_id, device_hash: hash] ++ details),
          on_conflict: {:replace, [:last_seen_at, :user_agent, :ip_address]},
          conflict_target: [:user_id, :device_hash]
        )

        if any?, do: :new, else: :first
      end
    end)
    |> case do
      {:ok, result} -> result
      {:error, _} -> :known
    end
  end

  defp hash(device_id), do: :crypto.hash(:sha256, device_id) |> Base.encode64()

  defp truncate(nil), do: nil
  defp truncate(text), do: String.slice(text, 0, 300)
end
