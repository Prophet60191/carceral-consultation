defmodule Claper.Accounts.UserDevice do
  @moduledoc """
  A browser an account has signed in from (`Claper.Accounts.KnownDevices`).
  The browser keeps a random ID in a cookie; only its hash is stored here.
  """
  use Ecto.Schema

  schema "user_devices" do
    field :device_hash, :string
    field :user_agent, :string
    field :ip_address, :string
    field :last_seen_at, :utc_datetime
    belongs_to :user, Claper.Accounts.User

    timestamps(updated_at: false)
  end
end
