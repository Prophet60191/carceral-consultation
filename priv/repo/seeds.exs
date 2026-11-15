# Script for populating the database. You can run it as:
#
#     mix run priv/repo/seeds.exs
#
# Inside the script, you can read and write to any of your
# repositories directly:
#
#     Claper.Repo.insert!(%Claper.SomeSchema{})
#
# We recommend using the bang functions (`insert!`, `update!`
# and so on) as they will fail if something goes wrong.

# Create roles if they don't exist
alias Claper.Accounts.Role
alias Claper.Repo

# Create admin role if it doesn't exist
if !Repo.get_by(Role, name: "admin") do
  %Role{name: "admin", permissions: %{"all" => true}}
  |> Repo.insert!()

  IO.puts("Created admin role")
end

# Create user role if it doesn't exist
if !Repo.get_by(Role, name: "user") do
  %Role{name: "user", permissions: %{}}
  |> Repo.insert!()

  IO.puts("Created user role")
end

# create a default active lti_1p3 jwk
if !Claper.Repo.get_by(Lti13.Jwks.Jwk, id: 1) do
  %{private_key: private_key} = Lti13.Jwks.Utils.KeyGenerator.generate_key_pair()

  Lti13.Jwks.create_jwk(%{
    pem: private_key,
    typ: "JWT",
    alg: "RS256",
    kid: UUID.uuid4(),
    active: true
  })
end

# No default account: a well-known password would be the first thing tried
# on a public copy (removed 2026-11-15). The first administrator is invited
# from the command line instead.
if Claper.Repo.aggregate(Claper.Accounts.User, :count, :id) == 0 do
  IO.puts("""
  No accounts yet. Invite the first administrator while the app is running:
    bin/claper rpc 'Claper.Release.create_admin("you@example.org")'
  """)
end

# Seed global settings defaults
Code.require_file("seeds/settings.exs", __DIR__)
