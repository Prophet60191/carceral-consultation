defmodule Claper.Breakouts.Sorter do
  @moduledoc """
  How the room is split into groups (docs/BREAKOUT.md, decisions 6–8).

    * Largest group size (the default): the fewest groups that keep every
      group at or under the size, with sizes within one of each other:
      23 at 5 → 5, 5, 5, 4, 4; 12 → 4, 4, 4; 7 → 4, 3.
    * Exact number of groups: that many groups (never more groups than
      people), sizes within one of each other.
    * People are shuffled before they are dealt into groups.
    * Packets are shared out in turn: with 3 packets, groups 1 and 4 get the
      first, 2 and 5 the second, 3 and 6 the third.
    * Groups are locked when the breakout starts (decision 24): people who
      arrive later are not put in a group; the presenter places them.
  """

  @type sizing :: {:max_size, pos_integer()} | {:group_count, pos_integer()}

  @doc "The size of each group for `n` people."
  @spec group_sizes(non_neg_integer(), sizing()) :: [pos_integer()]
  def group_sizes(0, _sizing), do: []

  def group_sizes(n, {:max_size, max}) when n > 0 and max > 0,
    do: spread(n, div(n + max - 1, max))

  def group_sizes(n, {:group_count, count}) when n > 0 and count > 0,
    do: spread(n, min(count, n))

  defp spread(n, groups) do
    base = div(n, groups)
    extra = rem(n, groups)
    for i <- 0..(groups - 1), do: base + if(i < extra, do: 1, else: 0)
  end

  @doc """
  Deals people into groups of the given sizes after shuffling them. The
  shuffle can be replaced (tests pass `& &1`).
  """
  @spec assign([term()], [pos_integer()], ([term()] -> [term()])) :: [[term()]]
  def assign(people, sizes, shuffle \\ &Enum.shuffle/1) do
    true = Enum.sum(sizes) == length(people)

    {groups, []} =
      Enum.map_reduce(sizes, shuffle.(people), fn size, rest -> Enum.split(rest, size) end)

    groups
  end

  @doc "The packet for the group at a 0-based index: packets are shared out in turn."
  @spec packet_for(non_neg_integer(), [term()]) :: term()
  def packet_for(index, packets) when packets != [],
    do: Enum.at(packets, rem(index, length(packets)))
end
