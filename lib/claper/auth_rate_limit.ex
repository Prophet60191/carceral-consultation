defmodule Claper.AuthRateLimit do
  @moduledoc """
  Limits on tries at a password or code (docs/SECURITY.md): the sign-in
  pages per address, sign-in per account, and LMS approval.

  A **sliding window**: a limit of 10 in 15 minutes means no more than 10 in
  *any* 15 minutes. With fixed windows (`Claper.RateLimit`, still used for
  chat and reactions), tries just before and just after a window turned over
  both counted as fresh, so someone timing it got twice the tries.

  Every try is its own row in an ETS `duplicate_bag` (`{key, time_ms}`), so
  tries at the same instant all count. (Hammer's sliding window keys rows by
  the microsecond and drops a second try in the same one.) Rows older than
  the longest window are swept every minute.
  """
  use GenServer

  @table __MODULE__
  @sweep_every :timer.minutes(1)
  # Longer than any window used with this module
  @keep_ms :timer.hours(2)

  def start_link(opts \\ []), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @doc "Counts a try and says whether it's within the limit."
  @spec attempt(term(), pos_integer(), pos_integer()) ::
          {:allow, pos_integer()} | {:deny, non_neg_integer()}
  def attempt(key, window_ms, limit) do
    record_failure(key, window_ms)
    count = count(key, window_ms)

    if count <= limit, do: {:allow, count}, else: {:deny, retry_after(key, window_ms)}
  end

  @doc "Has `key` reached `limit` tries in the last `window_ms`? Doesn't count a try."
  def blocked?(key, window_ms, limit), do: count(key, window_ms) >= limit

  @doc "Counts a failed try."
  def record_failure(key, _window_ms) do
    :ets.insert(@table, {key, now()})
    :ok
  end

  @doc """
  Forgets `key`'s tries: after a successful sign-in (NIST SP 800-63B-4: earlier
  failures are disregarded) or a password reset.
  """
  def clear(key) do
    :ets.delete(@table, key)
    :ok
  end

  @doc "Tries by `key` in the last `window_ms`."
  def count(key, window_ms) do
    since = now() - window_ms
    :ets.select_count(@table, [{{key, :"$1"}, [{:>, :"$1", since}], [true]}])
  end

  # Milliseconds until the oldest try in the window drops out
  defp retry_after(key, window_ms) do
    since = now() - window_ms

    case :ets.select(@table, [{{key, :"$1"}, [{:>, :"$1", since}], [:"$1"]}]) do
      [] -> 0
      times -> max(0, Enum.min(times) + window_ms - now())
    end
  end

  defp now, do: System.monotonic_time(:millisecond)

  @impl true
  def init(_opts) do
    :ets.new(@table, [
      :named_table,
      :duplicate_bag,
      :public,
      read_concurrency: true,
      write_concurrency: true
    ])

    schedule_sweep()
    {:ok, nil}
  end

  @impl true
  def handle_info(:sweep, state) do
    cutoff = now() - @keep_ms
    :ets.select_delete(@table, [{{:_, :"$1"}, [{:<, :"$1", cutoff}], [true]}])
    schedule_sweep()
    {:noreply, state}
  end

  defp schedule_sweep, do: Process.send_after(self(), :sweep, @sweep_every)
end
