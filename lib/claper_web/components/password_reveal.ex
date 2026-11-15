defmodule ClaperWeb.Component.PasswordReveal do
  @moduledoc """
  Password fields: the show/hide (eye) button, and the hints that let
  browsers and password managers suggest and save passwords (Jose,
  2026-11-15). Every password field in the app uses these.

  - `button/1` sits inside the field (the field's wrapper is `relative` and
    the input has room on the right, `pr-11`). Clicking it shows or hides
    the password. On live pages it uses LiveView JS commands, which survive
    the page's redraws, so a shown password stays shown while you type; on
    regular pages, `assets/js/password_reveal.js` does the same directly.
    Sending the form hides it again, so the browser offers to save it.
  - `account_hint/1` is a hidden field holding the account's email
    (`autocomplete="username"`). With it, a "choose a password" form tells
    the browser whose password this is, so it can suggest a strong one and
    save it for the right account.
  - `new_password_attrs/0`: on fields where someone chooses a password:
    `autocomplete="new-password"` (browsers offer a strong password),
    `minlength` and Safari's `passwordrules`, both 15 characters, matching
    `Claper.Accounts.PasswordPolicy`.
  """
  use Phoenix.Component
  use Gettext, backend: ClaperWeb.Gettext

  alias Phoenix.LiveView.JS

  @min_length 15

  attr :for, :string, required: true, doc: "the password input's id"

  def button(assigns) do
    show_label = gettext("Show password")
    hide_label = gettext("Hide password")

    assigns =
      assign(assigns,
        show_label: show_label,
        hide_label: hide_label,
        show_js: reveal(assigns.for, true, hide_label),
        hide_js: reveal(assigns.for, false, show_label)
      )

    ~H"""
    <button
      type="button"
      class="btn btn-ghost btn-square btn-sm group absolute inset-y-0 right-1 my-auto text-muted"
      data-password-reveal
      aria-controls={@for}
      aria-pressed="false"
      aria-label={@show_label}
      title={@show_label}
      data-label-show={@show_label}
      data-label-hide={@hide_label}
      data-show-js={@show_js}
      data-hide-js={@hide_js}
    >
      <svg
        class="size-5 group-aria-pressed:hidden"
        fill="none"
        viewBox="0 0 24 24"
        stroke-width="2"
        stroke="currentColor"
        aria-hidden="true"
      >
        <path
          stroke-linecap="round"
          stroke-linejoin="round"
          d="M2.036 12.322a1.012 1.012 0 010-.639C3.423 7.51 7.36 4.5 12 4.5c4.638 0 8.573 3.007 9.963 7.178.07.207.07.431 0 .639C20.577 16.49 16.64 19.5 12 19.5c-4.638 0-8.573-3.007-9.963-7.178z"
        />
        <path stroke-linecap="round" stroke-linejoin="round" d="M15 12a3 3 0 11-6 0 3 3 0 016 0z" />
      </svg>
      <svg
        class="hidden size-5 group-aria-pressed:block"
        fill="none"
        viewBox="0 0 24 24"
        stroke-width="2"
        stroke="currentColor"
        aria-hidden="true"
      >
        <path
          stroke-linecap="round"
          stroke-linejoin="round"
          d="M3.98 8.223A10.477 10.477 0 001.934 12C3.226 16.338 7.244 19.5 12 19.5c.993 0 1.953-.138 2.863-.395M6.228 6.228A10.45 10.45 0 0112 4.5c4.756 0 8.773 3.162 10.065 7.498a10.523 10.523 0 01-4.293 5.774M6.228 6.228L3 3m3.228 3.228l3.65 3.65m7.894 7.894L21 21m-3.228-3.228l-3.65-3.65m0 0a3 3 0 10-4.243-4.243m4.242 4.242L9.88 9.88"
        />
      </svg>
    </button>
    """
  end

  attr :email, :string, required: true

  @doc "A hidden field naming the account, for password managers (not sent)."
  def account_hint(assigns) do
    ~H"""
    <input
      type="email"
      value={@email}
      autocomplete="username"
      readonly
      tabindex="-1"
      aria-hidden="true"
      class="input sr-only"
    />
    """
  end

  @doc "Attributes for a field where someone chooses a new password."
  def new_password_attrs do
    [
      autocomplete: "new-password",
      minlength: @min_length,
      passwordrules: "minlength: #{@min_length};"
    ]
  end

  @doc "The shortest password the app accepts (Claper.Accounts.PasswordPolicy)."
  def min_length, do: @min_length

  # LiveView JS: the input's type, and the button's state and label. These
  # are kept through LiveView's redraws.
  defp reveal(id, show?, label) do
    JS.set_attribute({"type", if(show?, do: "text", else: "password")}, to: "##{id}")
    |> JS.set_attribute({"aria-pressed", to_string(show?)})
    |> JS.set_attribute({"aria-label", label})
    |> JS.set_attribute({"title", label})
  end
end
