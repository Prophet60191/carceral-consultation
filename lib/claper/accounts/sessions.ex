defmodule Claper.Accounts.Sessions do
  @moduledoc """
  A person's signed-in sessions, for My account › Sessions and activity
  (docs/SECURITY.md): where each was signed in from, and signing one or all
  of the others out.

  Every lookup is scoped to the person, so nobody can end someone else's
  session by guessing its number. Ending a session deletes its token (so
  "remember me" stops too) and disconnects its open pages.
  """
  import Ecto.Query

  alias Claper.Accounts.{User, UserToken}
  alias Claper.Repo

  # As long as a session lasts (UserToken)
  @session_days 60

  @doc "Open sessions, newest first, with `current: true` on the one holding `current_token`."
  def list(%User{id: user_id}, current_token) do
    from(t in UserToken,
      where:
        t.user_id == ^user_id and t.context == "session" and
          t.inserted_at > ago(@session_days, "day"),
      order_by: [desc: t.inserted_at, desc: t.id]
    )
    |> Repo.all()
    |> Enum.map(fn t ->
      %{
        id: t.id,
        browser: ClaperWeb.UserAgent.describe(t.user_agent),
        ip_address: t.ip_address,
        signed_in_at: t.inserted_at,
        current: is_binary(current_token) and Plug.Crypto.secure_compare(t.token, current_token)
      }
    end)
  end

  @doc "Ends one of the person's own sessions (never the current one: that's signing out)."
  def sign_out(%User{id: user_id}, id, current_token) do
    with {int_id, ""} <- Integer.parse(to_string(id)),
         %UserToken{} = t <-
           Repo.get_by(UserToken, id: int_id, user_id: user_id, context: "session"),
         false <- is_binary(current_token) and t.token == current_token do
      end_tokens([t])
      :ok
    else
      _ -> :error
    end
  end

  @doc "Ends every session but the current one. Returns how many."
  def sign_out_others(%User{id: user_id}, current_token) do
    others =
      Repo.all(
        from t in UserToken,
          where: t.user_id == ^user_id and t.context == "session" and t.token != ^current_token
      )

    end_tokens(others)
    {:ok, length(others)}
  end

  @doc "Deletes the tokens and disconnects their open pages."
  def end_tokens(tokens) do
    ids = Enum.map(tokens, & &1.id)
    Repo.delete_all(from t in UserToken, where: t.id in ^ids)

    for t <- tokens do
      ClaperWeb.Endpoint.broadcast(
        "users_sessions:#{Base.url_encode64(t.token)}",
        "disconnect",
        %{}
      )
    end

    :ok
  end
end
