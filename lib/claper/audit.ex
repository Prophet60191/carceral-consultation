defmodule Claper.Audit do
  @moduledoc """
  The Audit context for tracking actions in the system.
  """

  import Ecto.Query, only: [from: 2]

  alias Claper.{Accounts, Repo}
  alias Claper.Audit.Log

  @doc """
  Logs an action.

  ## Examples

      iex> log_action(user, "user.login", %{ip_address: "127.0.0.1"})
      {:ok, %Log{}}

      iex> log_action(nil, "system.startup", %{})
      {:ok, %Log{}}

  """
  def log_action(user, action, metadata \\ %{})

  def log_action(%Accounts.User{} = user, action, metadata) do
    create_log(%{
      user_id: user.id,
      action: action,
      metadata: metadata
    })
  end

  def log_action(nil, action, metadata) do
    create_log(%{
      action: action,
      metadata: metadata
    })
  end

  @doc """
  Records an account or administration event (docs/SECURITY.md, "Audit
  Log"). Never raises: a failed write is logged and the action goes on.

  - `actor`: who did it (`nil` when nobody is signed in)
  - `:target`: the account it was done to, when that's someone else (or the
    actor's own, for sign-in failures); stored as the resource, with its
    email in the metadata so the entry still reads after a deletion
  - `:resource`: `{type, id}` for anything else (a sign-in provider, ...)
  - `:metadata`: details. Never passwords, codes or keys.
  - `:context`: where it came from (`ip_address`, `user_agent`)
  """
  def record(actor, action, opts \\ []) do
    {resource_type, resource_id, target_meta} =
      case {opts[:target], opts[:resource]} do
        {%Accounts.User{} = target, _} -> {"user", target.id, %{target_email: target.email}}
        {_, {type, id}} -> {type, id, %{}}
        _ -> {nil, nil, %{}}
      end

    metadata =
      %{}
      |> Map.merge(target_meta)
      |> Map.merge(Map.new(opts[:context] || %{}))
      |> Map.merge(Map.new(opts[:metadata] || %{}))
      |> Map.reject(fn {_k, v} -> is_nil(v) end)

    attrs = %{
      user_id: actor && actor.id,
      action: action,
      resource_type: resource_type,
      resource_id: resource_id,
      metadata: metadata
    }

    case create_log(attrs) do
      {:ok, _} -> :ok
      {:error, reason} -> log_failure(action, reason)
    end
  rescue
    error -> log_failure(action, error)
  end

  defp log_failure(action, reason) do
    require Logger
    Logger.error("Audit log write failed for #{action}: #{inspect(reason)}")
    :ok
  end

  @doc """
  A person's own account history (My account › Sessions and activity):
  what they did, and what administrators did to their account. Newest
  first. Events and other people's actions aren't included.
  """
  def list_account_activity(%Accounts.User{id: id}, limit \\ 30) do
    from(l in Log,
      where:
        (l.user_id == ^id and
           (like(l.action, "user.%") or l.action == "security.rate_limit_exceeded")) or
          (l.resource_type == "user" and l.resource_id == ^id and l.user_id != ^id),
      order_by: [desc: l.inserted_at, desc: l.id],
      limit: ^limit
    )
    |> Repo.all()
  end

  @doc """
  Logs an action related to a specific resource.

  ## Examples

      iex> log_resource_action(user, "event.create", "event", 123, %{})
      {:ok, %Log{}}

  """
  def log_resource_action(
        %Accounts.User{} = user,
        action,
        resource_type,
        resource_id,
        metadata \\ %{}
      ) do
    create_log(%{
      user_id: user.id,
      action: action,
      resource_type: resource_type,
      resource_id: resource_id,
      metadata: metadata
    })
  end

  @doc """
  Returns a paginated, optionally filtered and sorted, list of audit logs.
  """
  def list_logs(params \\ %{}) do
    Flop.validate_and_run!(base_logs_query(), params, for: Log, replace_invalid_params: true)
  end

  @doc """
  Returns a paginated list of audit logs scoped to a single user.

  Accepts either a `Claper.Accounts.User` struct or a user id, plus the
  same Flop params used by `list_logs/1`.
  """
  def list_logs_for_user(user_or_id, params \\ %{})

  def list_logs_for_user(%Accounts.User{id: id}, params),
    do: list_logs_for_user(id, params)

  def list_logs_for_user(user_id, params) when is_integer(user_id) do
    query = from [l, _u] in base_logs_query(), where: l.user_id == ^user_id
    Flop.validate_and_run!(query, params, for: Log, replace_invalid_params: true)
  end

  defp base_logs_query do
    from l in Log, left_join: u in assoc(l, :user), as: :user, preload: [user: u]
  end

  @doc """
  Returns a list of distinct action types for filtering.
  """
  def list_action_types do
    from(l in Log,
      distinct: true,
      select: l.action,
      order_by: l.action
    )
    |> Repo.all()
  end

  @doc """
  Gets a single log.

  Raises `Ecto.NoResultsError` if the Log does not exist.

  ## Examples

      iex> get_log!(123)
      %Log{}

      iex> get_log!(456)
      ** (Ecto.NoResultsError)

  """
  def get_log!(id) do
    Repo.one!(
      from l in Log, left_join: u in assoc(l, :user), where: l.id == ^id, preload: [user: u]
    )
  end

  @doc """
  Creates a log entry.

  This is a simple wrapper over a low-level insert. You likely want to use
  `log_action/3` and `log_resource_action/5` instead.

  ## Examples

      iex> create_log(%{action: "user.login"})
      {:ok, %Log{}}

      iex> create_log(%{action: nil})
      {:error, %Ecto.Changeset{}}

  """
  def create_log(attrs \\ %{}) do
    %Log{}
    |> Log.changeset(attrs)
    |> Repo.insert()
  end
end
