defmodule Claper.Accounts.Administration do
  @moduledoc """
  What administrators can do to accounts, and the rules that keep it safe
  (docs/SECURITY.md, "Managing accounts").

  - **Roles** have two names people see: Administrator (`admin`) and
    Facilitator (`user`). The stored names stay as they were.
  - **Invitations**: an administrator invites someone by email; they set
    their own password from the link (7 days). The administrator never
    knows it.
  - **Guards**: nobody changes their own role or disables or deletes
    themselves, and the last active administrator can't be demoted,
    disabled or deleted. Checked here, on the server, whatever the page
    shows.
  - **Changes take effect at once**: a new role, or disabling someone,
    signs them out everywhere, open pages included. A new email address is
    confirmed by its owner first.
  """
  import Ecto.Query
  use Gettext, backend: ClaperWeb.Gettext

  alias Claper.Accounts
  alias Claper.Accounts.{Role, TwoFactor, User, UserToken}
  alias Claper.Repo
  alias Claper.Workers.Mailers

  ## Roles

  @doc "The role's name for people: Administrator or Facilitator."
  def role_label(%User{role: %Role{name: name}}), do: role_label(name)
  def role_label("admin"), do: gettext("Administrator")
  def role_label("user"), do: gettext("Facilitator")
  def role_label(name) when is_binary(name), do: String.capitalize(name)
  def role_label(_), do: gettext("No role")

  @doc "Role choices for a form: administrators first."
  def role_options do
    Accounts.list_roles()
    |> Enum.sort_by(&if(&1.name == "admin", do: 0, else: 1))
    |> Enum.map(&{role_label(&1.name), &1.id})
  end

  def admin?(%User{} = user), do: Accounts.user_has_role?(user, "admin")

  ## Guards

  @doc """
  May `actor` do `action` to `target`? `:ok` or `{:error, reason}`, where the
  reason is a sentence for the administrator.

  Actions: `:change_role`, `:disable`, `:delete`, `{:set_role, role_id}`.
  """
  def check(%User{id: id}, %User{id: id}, action) when action in [:disable, :delete],
    do: {:error, gettext("You can't disable or delete your own account here.")}

  def check(%User{id: id}, %User{id: id}, {:set_role, _}),
    do: {:error, gettext("You can't change your own role. Another administrator can.")}

  def check(_actor, %User{} = target, action) when action in [:disable, :delete] do
    if last_active_admin?(target),
      do:
        {:error,
         gettext("This is the last administrator. Make someone else an administrator first.")},
      else: :ok
  end

  def check(_actor, %User{} = target, {:set_role, role_id}) do
    target = Repo.preload(target, :role)
    to_admin? = admin_role_id() == to_int(role_id)

    if target.role && target.role.name == "admin" && !to_admin? && last_active_admin?(target),
      do:
        {:error,
         gettext("This is the last administrator. Make someone else an administrator first.")},
      else: :ok
  end

  defp last_active_admin?(%User{} = user) do
    admin?(user) and
      Repo.aggregate(
        from(u in User,
          join: r in assoc(u, :role),
          where: r.name == "admin" and is_nil(u.deleted_at) and u.id != ^user.id
        ),
        :count
      ) == 0
  end

  defp admin_role_id, do: (Accounts.get_role_by_name("admin") || %{id: nil}).id

  defp to_int(id) when is_integer(id), do: id

  defp to_int(id) when is_binary(id) do
    case Integer.parse(id) do
      {n, ""} -> n
      _ -> nil
    end
  end

  defp to_int(_), do: nil

  ## Invitations

  @doc "Invited and hasn't set a password yet."
  def invitation_pending?(%User{invited_at: invited, confirmed_at: confirmed}),
    do: not is_nil(invited) and is_nil(confirmed)

  @doc """
  Creates the account (no usable password) and emails the invitation.
  `url_fun` turns the link's token into its full address.
  """
  def invite(attrs, url_fun) when is_function(url_fun, 1) do
    attrs =
      attrs
      |> Map.new(fn {k, v} -> {to_string(k), v} end)
      |> Map.take(["email", "first_name", "last_name", "role_id"])
      |> Map.merge(%{
        # Random and never shown: nobody can sign in with it
        "password" => :crypto.strong_rand_bytes(32),
        "is_randomized_password" => true
      })

    Repo.transaction(fn ->
      with {:ok, user} <- Accounts.create_user(attrs, require_names: true),
           {:ok, user} <-
             user
             |> Ecto.Changeset.change(invited_at: now_naive(), confirmed_at: nil)
             |> Repo.update() do
        send_invitation(user, url_fun)
        user
      else
        {:error, changeset} -> Repo.rollback(changeset)
      end
    end)
  end

  @doc "A fresh link; earlier ones stop working."
  def resend_invitation(%User{} = user, url_fun) do
    if invitation_pending?(user) do
      send_invitation(user, url_fun)
      {:ok, user}
    else
      {:error, :not_pending}
    end
  end

  defp send_invitation(user, url_fun) do
    Repo.delete_all(UserToken.user_and_contexts_query(user, ["invitation"]))
    {token, user_token} = UserToken.build_email_token(user, "invitation")
    Repo.insert!(user_token)

    Mailers.new_invitation(user.id, url_fun.(token), user.locale || "en")
    |> Oban.insert()
  end

  @doc "The invited person, if the link is valid."
  def get_invited_user(token) do
    with {:ok, query} <- UserToken.verify_email_token_query(token, "invitation"),
         %User{} = user <- Repo.one(query),
         true <- invitation_pending?(user) do
      user
    else
      _ -> nil
    end
  end

  @doc "Sets their password (the usual rules) and confirms the account; spends the link."
  def accept_invitation(%User{} = user, params) do
    changeset =
      user
      |> User.password_changeset(Map.put(params, "is_randomized_password", false))
      |> Ecto.Changeset.put_change(:confirmed_at, now_naive())

    Ecto.Multi.new()
    |> Ecto.Multi.update(:user, changeset)
    |> Ecto.Multi.delete_all(:tokens, UserToken.user_and_contexts_query(user, ["invitation"]))
    |> Repo.transaction()
    |> case do
      {:ok, %{user: user}} -> {:ok, user}
      {:error, :user, changeset, _} -> {:error, changeset}
    end
  end

  ## Changes that take effect at once

  @doc """
  Ends every session of `user`: their tokens are deleted (so "remember me"
  stops working too) and open pages are disconnected.
  """
  def sign_out_everywhere(%User{} = user) do
    tokens =
      Repo.all(from t in UserToken, where: t.user_id == ^user.id and t.context == "session")

    Claper.Accounts.Sessions.end_tokens(tokens)
    {:ok, length(tokens)}
  end

  @doc "How many sessions `user` has open (not expired)."
  def open_sessions(%User{} = user) do
    Repo.aggregate(
      from(t in UserToken,
        where: t.user_id == ^user.id and t.context == "session" and t.inserted_at > ago(60, "day")
      ),
      :count
    )
  end

  @doc """
  An administrator changes someone's email address: the new address gets a
  link and the change happens when its owner opens it (signed in). For an
  invitation nobody has accepted yet, the address is simply corrected and
  the invitation sent again.
  """
  def change_email(%User{} = user, new_email, confirm_url_fun, invite_url_fun) do
    if invitation_pending?(user) do
      with {:ok, user} <- user |> User.email_changeset(%{email: new_email}) |> Repo.update() do
        send_invitation(user, invite_url_fun)
        {:ok, :invitation_resent, user}
      end
    else
      with {:ok, applied} <- Accounts.apply_user_email(user, %{"email" => new_email}) do
        Accounts.deliver_update_email_instructions(applied, user.email, confirm_url_fun)
        {:ok, :confirmation_sent, user}
      end
    end
  end

  @doc "Turns off two-step sign-in for someone who lost their phone and codes; signs them out."
  def reset_two_factor(%User{} = user) do
    with {:ok, user} <- TwoFactor.disable(user) do
      sign_out_everywhere(user)
      Claper.Accounts.SecurityNotices.two_factor_off(user, :admin)
      {:ok, user}
    end
  end

  @doc "Records a sign-in, for the Users page."
  def touch_last_sign_in(%User{id: id}) do
    Repo.update_all(from(u in User, where: u.id == ^id),
      set: [last_signed_in_at: DateTime.utc_now() |> DateTime.truncate(:second)]
    )

    :ok
  end

  defp now_naive, do: NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)
end
