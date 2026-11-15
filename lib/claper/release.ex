defmodule Claper.Release do
  @moduledoc """
  Used for executing DB release tasks when run in production without Mix
  installed.
  """
  @app :claper

  def migrate do
    load_app()

    Application.ensure_all_started(:ssl)

    for repo <- repos() do
      {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :up, all: true))
    end
  end

  def seeds do
    load_app()

    for repo <- repos() do
      {:ok, _, _} =
        Ecto.Migrator.with_repo(repo, fn _repo ->
          seed_script = Application.app_dir(@app, "priv/repo/seeds.exs")
          Code.eval_file(seed_script)
        end)
    end
  end

  @doc """
  Turns off two-step sign-in for one account, for an administrator who lost
  both the phone and the backup codes (docs/SECURITY.md). Run on the server:

      bin/claper eval 'Claper.Release.reset_two_factor("person@example.org")'

  They sign in with their password and, if two-step sign-in is required for
  them, set it up again straight away.
  """
  def reset_two_factor(email) when is_binary(email) do
    load_app()

    for repo <- repos() do
      {:ok, _, _} =
        Ecto.Migrator.with_repo(repo, fn _repo ->
          case Claper.Accounts.get_user_by_email(email) do
            nil ->
              IO.puts("No account with that email address.")

            user ->
              {:ok, _} = Claper.Accounts.TwoFactor.disable(user)
              IO.puts("Two-step sign-in is off for #{email}.")
          end
        end)
    end
  end

  @doc """
  Invites the first administrator of a new copy (2026-11-15; there is no
  default account or password). Run on the server while the app is running:

      bin/claper rpc 'Claper.Release.create_admin("you@example.org")'

  The account gets a random password nobody knows. The invitation link is
  printed here and also emailed when email is set up; it works for 7 days,
  and the person chooses their own password with it. Returns the link.
  """
  def create_admin(email, first_name \\ "Admin", last_name \\ "User")
      when is_binary(email) do
    case Claper.Accounts.get_role_by_name("admin") do
      nil ->
        # The roles are created by the seeds on every start
        IO.puts("No admin role yet: start the app once (it creates the roles), then try again.")
        {:error, :no_admin_role}

      role ->
        invite_admin(email, first_name, last_name, role)
    end
  end

  defp invite_admin(email, first_name, last_name, role) do
    me = self()

    url_fun = fn token ->
      url = ClaperWeb.Endpoint.url() <> "/users/invitation/" <> token
      send(me, {:invitation_url, url})
      url
    end

    attrs = %{email: email, first_name: first_name, last_name: last_name, role_id: role.id}

    case Claper.Accounts.Administration.invite(attrs, url_fun) do
      {:ok, _user} ->
        receive do
          {:invitation_url, url} ->
            IO.puts("Administrator invited: #{email}")
            IO.puts("Open this link to choose a password (valid 7 days):")
            IO.puts(url)
            {:ok, url}
        after
          0 -> {:error, :no_link}
        end

      {:error, changeset} ->
        IO.puts("Could not invite #{email}: #{inspect(changeset.errors)}")
        {:error, changeset}
    end
  end

  def rollback(repo, version) do
    load_app()
    {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :down, to: version))
  end

  defp repos do
    Application.fetch_env!(@app, :ecto_repos)
  end

  defp load_app do
    Application.load(@app)
  end
end
