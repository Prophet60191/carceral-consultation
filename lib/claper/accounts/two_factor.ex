defmodule Claper.Accounts.TwoFactor do
  @moduledoc """
  Two-step sign-in (docs/SECURITY.md): after the password, a 6-digit code
  from an authenticator app (TOTP, RFC 6238, via `NimbleTOTP`), or one of ten
  single-use backup codes.

  - The authenticator secret is stored encrypted with the app's secret key;
    backup codes only as hashes, shown once when made.
  - A code can't be used twice (`totp_last_used_at`), and the code from the
    30 seconds before is still taken, for clocks that drift.
  - Each person chooses, with the switch in My account (Jose,
    2026-11-15), unless Admin › Settings › "Require two-step sign-in for
    everyone" (`two_factor_required`) is on: then everyone must use it,
    administrators included, and nobody can turn it off.
  - Sign-in through an outside provider (OIDC, LMS) doesn't ask: that
    provider runs its own checks.

  Lost both the phone and the backup codes? An administrator can turn it
  off for someone; for the last administrator, the server can
  (`Claper.Release.reset_two_factor/1`).
  """
  import Ecto.Changeset

  alias Claper.Accounts.User
  alias Claper.Repo

  @salt "two-factor secret"
  @backup_code_count 10
  # Codes shown by the app: groups of 5 for reading; no 0/O/1/I to misread
  @alphabet ~c"abcdefghjkmnpqrstuvwxyz23456789"

  @spec enabled?(User.t()) :: boolean()
  def enabled?(%User{totp_enabled_at: at, totp_secret: secret}),
    do: not is_nil(at) and is_binary(secret)

  @doc "Must this person use two-step sign-in? Only when the administrators require it for everyone."
  def required?(%User{} = _user), do: Claper.Settings.get("two_factor_required") == "true"

  @doc "Must turn it on before going further: required, and not on yet."
  def setup_needed?(%User{} = user), do: not enabled?(user) and required?(user)

  @doc "A new secret, not saved until a code from it is confirmed."
  def new_secret, do: NimbleTOTP.secret()

  @doc "What the authenticator app's QR code holds."
  def otpauth_uri(%User{email: email}, secret) do
    issuer = Claper.Branding.name(Claper.Branding.get())
    NimbleTOTP.otpauth_uri("#{issuer}:#{email}", secret, issuer: issuer)
  end

  @doc "The secret as letters, for typing into an app by hand."
  def secret_text(secret) do
    secret
    |> Base.encode32(padding: false)
    |> String.graphemes()
    |> Enum.chunk_every(4)
    |> Enum.map_join(" ", &Enum.join/1)
  end

  @doc """
  Turns it on once a code from `secret` checks out. Returns the backup codes,
  shown to the person once.
  """
  def enable(%User{} = user, secret, code, at \\ System.os_time(:second)) do
    now = DateTime.from_unix!(at)

    if valid_totp?(secret, code, nil, now) do
      codes = new_backup_codes()

      user
      |> change(
        totp_secret: encrypt(secret),
        totp_enabled_at: NaiveDateTime.truncate(NaiveDateTime.utc_now(), :second),
        totp_last_used_at: now,
        backup_code_hashes: Enum.map(codes, &hash_code/1)
      )
      |> Repo.update()
      |> case do
        {:ok, user} -> {:ok, user, codes}
        error -> error
      end
    else
      {:error, :invalid_code}
    end
  end

  def disable(%User{} = user) do
    user
    |> change(
      totp_secret: nil,
      totp_enabled_at: nil,
      totp_last_used_at: nil,
      backup_code_hashes: []
    )
    |> Repo.update()
  end

  @doc "New backup codes; the old ones stop working."
  def regenerate_backup_codes(%User{} = user) do
    codes = new_backup_codes()

    case user |> change(backup_code_hashes: Enum.map(codes, &hash_code/1)) |> Repo.update() do
      {:ok, user} -> {:ok, user, codes}
      error -> error
    end
  end

  def backup_codes_left(%User{backup_code_hashes: hashes}), do: length(hashes || [])

  @doc """
  Checks a code at sign-in: an authenticator code, or a backup code (used up).
  Returns `{:ok, user, :totp | :backup_code}` or `:error`.
  """
  def verify(%User{} = user, code) when is_binary(code) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)
    digits = String.replace(code, ~r/\s/, "")

    with true <- enabled?(user),
         {:ok, secret} <- decrypt(user.totp_secret) do
      cond do
        valid_totp?(secret, digits, user.totp_last_used_at, now) ->
          {:ok, user} = user |> change(totp_last_used_at: now) |> Repo.update()
          {:ok, user, :totp}

        hash = matching_backup_code(user, code) ->
          {:ok, user} =
            user
            |> change(backup_code_hashes: List.delete(user.backup_code_hashes, hash))
            |> Repo.update()

          {:ok, user, :backup_code}

        true ->
          :error
      end
    else
      _ -> :error
    end
  end

  def verify(_user, _code), do: :error

  # This 30-second window or the one before; never a code already used
  defp valid_totp?(secret, code, since, now) do
    unix = DateTime.to_unix(now)

    Enum.any?([unix, unix - 30], fn time ->
      NimbleTOTP.valid?(secret, code, time: time, since: since)
    end)
  end

  defp matching_backup_code(%User{backup_code_hashes: hashes}, code) do
    hash = hash_code(code)
    Enum.find(hashes || [], &Plug.Crypto.secure_compare(&1, hash))
  end

  defp new_backup_codes do
    for _ <- 1..@backup_code_count do
      chars = for _ <- 1..10, do: random_char()
      {a, b} = Enum.split(chars, 5)
      "#{a}-#{b}"
    end
  end

  # From the system's cryptographic random source; bytes that would make some
  # letters likelier than others are drawn again.
  defp random_char do
    size = length(@alphabet)
    <<byte>> = :crypto.strong_rand_bytes(1)

    if byte < div(256, size) * size,
      do: Enum.at(@alphabet, rem(byte, size)),
      else: random_char()
  end

  # Codes are random (about 50 bits each) and single-use, so a plain hash is
  # enough; typing them with spaces, dashes or capitals still matches.
  defp hash_code(code) do
    normalized = code |> String.downcase() |> String.replace(~r/[^a-z0-9]/, "")
    :crypto.hash(:sha256, normalized) |> Base.encode64()
  end

  defp encrypt(secret), do: Plug.Crypto.encrypt(key(), @salt, secret, max_age: :infinity)

  defp decrypt(nil), do: :error

  defp decrypt(encrypted) do
    case Plug.Crypto.decrypt(key(), @salt, encrypted, max_age: :infinity) do
      {:ok, secret} -> {:ok, secret}
      _ -> :error
    end
  end

  defp key, do: ClaperWeb.Endpoint.config(:secret_key_base)
end
