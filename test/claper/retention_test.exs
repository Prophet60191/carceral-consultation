defmodule Claper.RetentionTest do
  @moduledoc "Sign-in records are deleted after RECORD_RETENTION_DAYS (Claper.Retention)."
  use Claper.DataCase, async: false

  import Claper.AccountsFixtures

  alias Claper.{Repo, Retention}
  alias Claper.Accounts.{UserDevice, UserToken}
  alias Claper.Audit.Log

  setup do
    previous = Application.get_env(:claper, :record_retention_days)
    on_exit(fn -> Application.put_env(:claper, :record_retention_days, previous) end)
    %{user: user_fixture()}
  end

  defp days_ago(days),
    do:
      NaiveDateTime.utc_now()
      |> NaiveDateTime.add(-days * 86_400)
      |> NaiveDateTime.truncate(:second)

  defp records(user, days) do
    at = days_ago(days)
    Repo.insert!(%Log{action: "user.login", user_id: user.id, inserted_at: at})

    Repo.insert!(%UserToken{
      user_id: user.id,
      token: :crypto.strong_rand_bytes(32),
      context: "session",
      ip_address: "203.0.113.9",
      inserted_at: at
    })

    Repo.insert!(%UserDevice{
      user_id: user.id,
      device_hash: "hash-#{days}",
      user_agent: "Test",
      ip_address: "203.0.113.9",
      last_seen_at: at |> DateTime.from_naive!("Etc/UTC"),
      inserted_at: at
    })
  end

  defp counts,
    do:
      {Repo.aggregate(Log, :count), Repo.aggregate(UserToken, :count),
       Repo.aggregate(UserDevice, :count)}

  test "records older than the limit go; newer ones stay", %{user: user} do
    Application.put_env(:claper, :record_retention_days, 365)
    {logs, tokens, devices} = counts()
    records(user, 400)
    records(user, 30)

    assert Retention.prune() == %{audit_logs: 1, tokens: 1, devices: 1}
    assert counts() == {logs + 1, tokens + 1, devices + 1}
  end

  test "0 keeps everything", %{user: user} do
    Application.put_env(:claper, :record_retention_days, 0)
    records(user, 4000)
    before = counts()

    assert Retention.prune() == :disabled
    assert counts() == before
  end

  test "it runs every day", %{user: _user} do
    crontab =
      Application.get_env(:claper, Oban)[:plugins]
      |> Enum.find_value(fn
        {Oban.Plugins.Cron, opts} -> opts[:crontab]
        _ -> nil
      end)

    assert {"@daily", Claper.Workers.RecordRetention} in crontab
    assert :ok = perform_job(Claper.Workers.RecordRetention, %{})
  end
end
