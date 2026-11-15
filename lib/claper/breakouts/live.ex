defmodule Claper.Breakouts.Live do
  @moduledoc """
  Running a breakout live (docs/BREAKOUT.md, steps 4–5): each action here
  does its work through `Claper.Breakouts` and then tells every screen of
  the event, on the event's channel (`"event:<uuid>"`, which the phones, the
  manage screen and the presenter screen already listen to).

  Messages carry only what changed and which run and group it concerns.
  Each listening LiveView reloads what its own viewer may see from the
  database, so a phone never receives another group's material; filtering
  happens on the server.

    * `{:breakout, :changed, run_id}` — started, stopped, timer, reporting back
    * `{:breakout, :group, run_id, group_id}` — membership or note-taker changed
    * `{:breakout, :answer, run_id, group_id}` — an answer was saved
    * `{:breakout, :message, run_id, group_id | nil, text}` — a message from
      the presenter, to one group or (nil) to every group
  """
  alias Claper.Breakouts
  alias Claper.Breakouts.{Breakout, Group, Run}

  def start(%Breakout{} = breakout, identifiers) do
    with {:ok, run} <- Breakouts.start_run(breakout, identifiers) do
      broadcast(breakout, {:breakout, :changed, run.id})
      {:ok, run}
    end
  end

  def stop(%Run{} = run), do: run_change(run, Breakouts.stop_run(run))
  def add_time(%Run{} = run, minutes), do: run_change(run, Breakouts.add_time(run, minutes))
  def show_group(%Run{} = run, group_id), do: run_change(run, Breakouts.show_group(run, group_id))

  def claim_note_taker(%Run{} = run, %Group{} = group, identifier),
    do: group_change(run, group, Breakouts.claim_note_taker(group, identifier))

  def hand_off_note_taker(%Run{} = run, %Group{} = group, identifier),
    do: group_change(run, group, Breakouts.hand_off_note_taker(group, identifier))

  @doc "Frees the role if `identifier` still holds it (their phone has been gone a while)."
  def release_absent_note_taker(%Run{} = run, %Group{} = group, identifier) do
    case Breakouts.clear_note_taker_if(group, identifier) do
      {:ok, group} ->
        broadcast_run(run, {:breakout, :group, run.id, group.id})
        {:ok, group}

      :unchanged ->
        :unchanged
    end
  end

  def answer(%Run{} = run, piece, identifier, params) do
    with {:ok, answer} <- Breakouts.put_answer(run, piece, identifier, params) do
      broadcast_run(run, {:breakout, :answer, run.id, answer.group_id})
      {:ok, answer}
    end
  end

  def withdraw(%Run{} = run, piece, identifier) do
    with {:ok, group_id} <- Breakouts.withdraw_answer(run, piece, identifier) do
      broadcast_run(run, {:breakout, :answer, run.id, group_id})
      :ok
    end
  end

  @doc "A message from the presenter to one group, or to every group (`group_id` nil)."
  def message(%Run{} = run, group_id, text) when is_binary(text) do
    case String.trim(text) do
      "" ->
        {:error, :empty}

      text ->
        broadcast_run(run, {:breakout, :message, run.id, group_id, String.slice(text, 0, 500)})
        :ok
    end
  end

  defp run_change(run, {:ok, updated}) do
    broadcast_run(run, {:breakout, :changed, run.id})
    {:ok, updated}
  end

  defp run_change(_run, error), do: error

  defp group_change(run, group, {:ok, updated}) do
    broadcast_run(run, {:breakout, :group, run.id, group.id})
    {:ok, updated}
  end

  defp group_change(_run, _group, error), do: error

  defp broadcast_run(%Run{breakout_id: breakout_id}, message),
    do: broadcast(%Breakout{id: breakout_id, presentation_file_id: pf_id(breakout_id)}, message)

  defp pf_id(breakout_id), do: Claper.Repo.get!(Breakout, breakout_id).presentation_file_id

  defp broadcast(%Breakout{} = breakout, message) do
    case Breakouts.event_uuid(breakout) do
      nil -> :ok
      uuid -> Phoenix.PubSub.broadcast(Claper.PubSub, "event:#{uuid}", message)
    end
  end
end
