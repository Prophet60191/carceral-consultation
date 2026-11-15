defmodule Claper.Repo.Migrations.AddDeviceDetailsToUsersTokens do
  use Ecto.Migration

  # My account › Sessions and activity: which browser and address each
  # signed-in session came from (docs/SECURITY.md).
  def change do
    alter table(:users_tokens) do
      add :user_agent, :string, size: 300
      add :ip_address, :string
    end
  end
end
