defmodule Claper.AuthRateLimitTest do
  @moduledoc "Sign-in limits count in a sliding window (docs/SECURITY.md)."
  use ExUnit.Case, async: true

  alias Claper.AuthRateLimit

  defp key, do: "test:#{System.unique_integer([:positive])}"

  test "no reset point: tries stay counted for the whole window from each try" do
    key = key()
    for _ <- 1..3, do: AuthRateLimit.record_failure(key, 1_000)
    assert AuthRateLimit.blocked?(key, 1_000, 3)

    # A fixed one-second window could have turned over by now; a sliding one
    # still holds all three
    Process.sleep(700)
    assert AuthRateLimit.blocked?(key, 1_000, 3)

    Process.sleep(450)
    refute AuthRateLimit.blocked?(key, 1_000, 3)
  end

  test "checking doesn't count as a try" do
    key = key()
    for _ <- 1..5, do: refute(AuthRateLimit.blocked?(key, 60_000, 3))
    AuthRateLimit.record_failure(key, 60_000)
    refute AuthRateLimit.blocked?(key, 60_000, 3)
  end

  test "attempt/3 counts every try" do
    key = key()
    assert {:allow, 1} = AuthRateLimit.attempt(key, 60_000, 2)
    assert {:allow, 2} = AuthRateLimit.attempt(key, 60_000, 2)
    assert {:deny, _} = AuthRateLimit.attempt(key, 60_000, 2)
  end

  test "clear/1 forgets a key's tries, and only that key's" do
    [a, b] = [key(), key()]
    for k <- [a, b], _ <- 1..3, do: AuthRateLimit.record_failure(k, 60_000)

    AuthRateLimit.clear(a)
    refute AuthRateLimit.blocked?(a, 60_000, 3)
    assert AuthRateLimit.blocked?(b, 60_000, 3)
  end
end
