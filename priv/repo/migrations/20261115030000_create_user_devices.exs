defmodule Claper.Repo.Migrations.CreateUserDevices do
  use Ecto.Migration

  # Browsers each account has signed in from, for the new-device email
  # (docs/SECURITY.md). The browser's random ID is kept only as a hash.
  def change do
    create table(:user_devices) do
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :device_hash, :string, null: false
      add :user_agent, :string, size: 300
      add :ip_address, :string
      add :last_seen_at, :utc_datetime, null: false

      timestamps(updated_at: false)
    end

    create unique_index(:user_devices, [:user_id, :device_hash])
  end
end
