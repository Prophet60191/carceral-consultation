defmodule Claper.Repo.Migrations.AddInvitationAndLastSignInToUsers do
  use Ecto.Migration

  # Invitations (an administrator invites; the person sets their own
  # password) and the Users page's "last sign-in" (docs/SECURITY.md).
  def change do
    alter table(:users) do
      add :invited_at, :naive_datetime
      add :last_signed_in_at, :utc_datetime
    end
  end
end
