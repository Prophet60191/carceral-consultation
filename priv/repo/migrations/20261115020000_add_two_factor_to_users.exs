defmodule Claper.Repo.Migrations.AddTwoFactorToUsers do
  use Ecto.Migration

  # Two-step sign-in (docs/SECURITY.md). The authenticator secret is stored
  # encrypted with the app's secret key; backup codes only as hashes.
  def change do
    alter table(:users) do
      add :totp_secret, :binary
      add :totp_enabled_at, :naive_datetime
      # The last time a code was accepted: a code can't be used twice
      add :totp_last_used_at, :utc_datetime
      add :backup_code_hashes, {:array, :string}, null: false, default: []
    end
  end
end
