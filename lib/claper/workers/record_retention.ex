defmodule Claper.Workers.RecordRetention do
  @moduledoc """
  Deletes sign-in records older than `RECORD_RETENTION_DAYS` (see
  `Claper.Retention`). Scheduled daily by `Oban.Plugins.Cron`.
  """
  use Oban.Worker, queue: :default

  require Logger

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    case Claper.Retention.prune() do
      :disabled ->
        :ok

      counts ->
        Logger.info("Record retention: deleted #{inspect(counts)}")
        :ok
    end
  end
end
