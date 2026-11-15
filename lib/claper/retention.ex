defmodule Claper.Retention do
  @moduledoc """
  How long sign-in records are kept (2026-11-15, agreed with Jose before the
  app went public; the privacy page states it).

  After `RECORD_RETENTION_DAYS` days (default 365; `0` keeps everything),
  these are deleted:

  - Audit Log entries (`audit_logs`): actions, with the address and device
    they came from
  - sign-in and account tokens (`users_tokens`), which hold the address and
    device of each sign-in. Sessions end after 60 days anyway, so a value
    under 60 also signs people out sooner.
  - remembered devices (`user_devices`) not seen in that time; signing in
    from one again sends a new-device email

  Event content (messages, answers, forms, attendance) is kept until the
  event is deleted, and accounts until they are deleted.

  Run daily by `Claper.Workers.RecordRetention`.
  """
  import Ecto.Query

  alias Claper.Repo
  alias Claper.Accounts.{UserDevice, UserToken}
  alias Claper.Audit.Log

  @default_days 365

  @doc "Days records are kept; `0` keeps them."
  def days, do: Application.get_env(:claper, :record_retention_days, @default_days)

  @doc """
  Deletes the records older than `days/0` as of `now`. Returns how many of
  each went, or `:disabled`.
  """
  def prune(now \\ NaiveDateTime.utc_now()) do
    case days() do
      days when is_integer(days) and days > 0 ->
        cutoff = NaiveDateTime.add(now, -days * 86_400, :second)

        {audit, _} = Repo.delete_all(from(l in Log, where: l.inserted_at < ^cutoff))
        {tokens, _} = Repo.delete_all(from(t in UserToken, where: t.inserted_at < ^cutoff))

        # Devices are stamped as UTC datetimes; the rest as naive UTC
        seen_cutoff = cutoff |> DateTime.from_naive!("Etc/UTC") |> DateTime.truncate(:second)

        {devices, _} =
          Repo.delete_all(from(d in UserDevice, where: d.last_seen_at < ^seen_cutoff))

        %{audit_logs: audit, tokens: tokens, devices: devices}

      _ ->
        :disabled
    end
  end
end
