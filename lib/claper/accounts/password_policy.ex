defmodule Claper.Accounts.PasswordPolicy do
  @moduledoc """
  What a new password must be (docs/SECURITY.md), following NIST SP 800-63B-4
  section 3.1.1.2:

  - **At least 15 characters.** NIST's minimum for a password that may be an
    account's only protection; two-step sign-in is optional for facilitators.
    No rules about mixing letters, digits or symbols (NIST: SHALL NOT).
  - **At most 72 bytes**, bcrypt's limit (at least 64 characters for
    ordinary text, as NIST asks).
  - **Not a known breached password** (`Claper.Accounts.PwnedPasswords`).
  - **Not the person's name or email, or the app's name**, or those with
    numbers or symbols added.
  - **A refusal always says why.**

  Existing passwords keep working: NIST rules out forcing changes on a
  schedule. Checked when a password is set or changed, never at sign-in.
  """
  import Ecto.Changeset
  use Gettext, backend: ClaperWeb.Gettext

  alias Claper.Accounts.PwnedPasswords

  @min_length 15
  @max_bytes 72

  def min_length, do: @min_length

  @doc "Length rules: cheap, so also used while the person types."
  def validate_length(changeset) do
    changeset
    |> validate_length(:password,
      min: @min_length,
      message:
        gettext(
          "Use at least %{count} characters. A short sentence or a few words together works well.",
          count: @min_length
        )
    )
    |> validate_length(:password,
      max: @max_bytes,
      count: :bytes,
      message: gettext("Use at most 72 characters (fewer if it has accents or emoji).")
    )
  end

  @doc "The full check, when a password is actually being saved."
  def validate(changeset) do
    changeset = validate_length(changeset)
    password = get_change(changeset, :password)

    cond do
      not changeset.valid? or not is_binary(password) ->
        changeset

      # Made by the server for accounts that sign in elsewhere (OIDC, LMS):
      # random, never typed, so the checks for chosen passwords don't apply
      get_field(changeset, :is_randomized_password) == true or not String.valid?(password) ->
        changeset

      personal?(password, changeset) ->
        add_error(
          changeset,
          :password,
          gettext("Don't use your name, your email address or the app's name as a password.")
        )

      PwnedPasswords.check(password) == :breached ->
        add_error(
          changeset,
          :password,
          gettext(
            "This password has appeared in a data breach, so attackers try it first. Choose a different one."
          )
        )

      true ->
        changeset
    end
  end

  # The whole password compared with each context word, ignoring case,
  # spaces, symbols and digits ("CarceralConsultation2026!" counts).
  defp personal?(password, changeset) do
    candidate = normalize(password)

    candidate != "" and candidate in context_words(changeset)
  end

  defp context_words(changeset) do
    email = get_field(changeset, :email) || ""
    first = get_field(changeset, :first_name) || ""
    last = get_field(changeset, :last_name) || ""
    local = email |> String.split("@") |> List.first()

    [
      email,
      local,
      first,
      last,
      first <> last,
      last <> first,
      Claper.Branding.name(Claper.Branding.get()),
      "claper",
      "password"
    ]
    |> Enum.map(&normalize/1)
    |> Enum.reject(&(&1 == ""))
  end

  defp normalize(text) do
    text
    |> String.downcase()
    |> String.replace(~r/[^\p{L}]/u, "")
  end
end
