defmodule ClaperWeb.Landing do
  @moduledoc """
  The landing page (Jose, 2026-11-15): the front door for everyone. The
  brand's photo fills the screen with its name and description (Brand
  page); "Join event" and "Log in" (top right) open a panel on the right
  and the photo narrows to make room. On phones the photo shrinks to a
  banner and the panel comes up below it.

  One page, three addresses: `/` (closed), `/join` (Join open, the live
  page `ClaperWeb.EventLive.Join`) and `/users/log_in` (Log in open, a
  regular page so a wrong password re-renders with its error). Opening a
  panel from the page adds `#join` / `#log-in` to the address, so Back
  closes it (assets/js/landing.js, styles in assets/css/landing.css).

  Both forms work with or without LiveView: the join form submits to
  `/join?event[code]=…` (LiveView catches it first where it runs), and the
  login form posts to `/users/log_in`.
  """
  use Phoenix.Component
  use Gettext, backend: ClaperWeb.Gettext

  use Phoenix.VerifiedRoutes,
    endpoint: ClaperWeb.Endpoint,
    router: ClaperWeb.Router,
    statics: ClaperWeb.static_paths()

  import PhoenixHTMLHelpers.Link, only: [link: 2]

  alias Claper.Branding

  @position %{"left" => "bg-left", "center" => "bg-center", "right" => "bg-right"}

  attr :initial, :atom, values: [:none, :join, :login], default: :none
  attr :current_user, :any, default: nil
  attr :error_message, :string, default: nil
  attr :last_event, :any, default: nil

  def page(assigns) do
    brand = Branding.get()

    assigns =
      assign(assigns,
        brand: brand,
        photo: brand.photo_src,
        position: Map.get(@position, brand.photo_position || "center", "bg-center"),
        description: Branding.description(brand),
        oidc: Application.get_env(:claper, :oidc) || []
      )

    ~H"""
    <div class="landing" data-landing-root data-landing-initial={@initial}>
      <%!-- Over the photo: drawn in its (dark) theme --%>
      <nav
        class="landing-bar bg-transparent"
        data-theme={@photo && "carceral"}
        aria-label={gettext("Join or log in")}
      >
        <button
          type="button"
          data-landing-open="join"
          aria-controls="landing-panel"
          class="btn btn-primary"
        >
          {gettext("Join event")}
        </button>
        <.link :if={@current_user} href={~p"/events"} class="btn btn-outline">
          {gettext("My events")}
        </.link>
        <button
          :if={!@current_user}
          type="button"
          data-landing-open="login"
          aria-controls="landing-panel"
          class="btn btn-outline"
        >
          {gettext("Log in")}
        </button>
      </nav>

      <section
        data-theme={@photo && "carceral"}
        class={["landing-photo text-base-content", @photo && @position, !@photo && "bg-base-200"]}
        style={@photo && "background-image: url('#{@photo}');"}
      >
        <%!-- A soft shade along the top keeps the buttons readable on any photo --%>
        <div
          :if={@photo}
          class="absolute inset-x-0 top-0 h-28 bg-linear-to-b from-scrim/60 to-transparent"
        >
        </div>
        <%!-- Darkened under the text so it stays readable --%>
        <div
          :if={@photo}
          class="absolute inset-0 bg-linear-to-tr from-scrim/90 via-scrim/45 to-transparent"
        >
        </div>
        <div class="landing-photo-text space-y-4">
          <ClaperWeb.Wordmark.mark
            size={:none}
            class="w-full text-base-content [--wm-h:clamp(2rem,4vw,4rem)]"
          />
          <p class="landing-photo-extra text-base leading-7 text-base-content lg:text-lg lg:leading-8">
            {@description}
          </p>
          <p class="landing-photo-extra flex flex-wrap gap-x-4 gap-y-1 text-sm">
            <a
              href="/about"
              class="text-muted underline-offset-4 hover:text-base-content hover:underline"
            >
              {gettext("About this app")}
            </a>
            <a
              href={ClaperWeb.Privacy.url()}
              class="text-muted underline-offset-4 hover:text-base-content hover:underline"
            >
              {gettext("Privacy")}
            </a>
          </p>
        </div>
      </section>

      <section id="landing-panel" class="landing-panel" aria-label={gettext("Join or log in")}>
        <div class="landing-panel-body">
          <div class="w-full max-w-md">
            <button
              type="button"
              data-landing-close
              class="btn btn-ghost btn-sm mb-6 -ml-3"
              aria-label={gettext("Close")}
            >
              <svg
                class="size-4"
                fill="none"
                stroke="currentColor"
                viewBox="0 0 24 24"
                aria-hidden="true"
              >
                <path
                  stroke-linecap="round"
                  stroke-linejoin="round"
                  stroke-width="2"
                  d="M15 19l-7-7 7-7"
                />
              </svg>
              {gettext("Back")}
            </button>

            <div class="landing-form" data-landing-panel="join">
              <.join_form last_event={@last_event} />
            </div>
            <div class="landing-form" data-landing-panel="login">
              <.login_form error_message={@error_message} oidc={@oidc} />
            </div>

            <%!-- On phones the banner shows only the name; the license
                 notices stay within reach here (AGPL-3.0, section 13) --%>
            <p class="mt-10 flex justify-center gap-4 text-sm md:hidden">
              <a href="/about" class="text-muted hover:text-base-content">
                {gettext("About this app")}
              </a>
              <a href={ClaperWeb.Privacy.url()} class="text-muted hover:text-base-content">
                {gettext("Privacy")}
              </a>
            </p>
          </div>
        </div>
      </section>
    </div>
    """
  end

  attr :last_event, :any, default: nil

  defp join_form(assigns) do
    ~H"""
    <div class="space-y-6">
      <div>
        <h2 class="text-3xl font-bold text-base-content lg:text-4xl">
          {gettext("Join the event")}
        </h2>
        <p class="mt-3 text-base text-muted">{gettext("Enter the code shared by the presenter")}</p>
      </div>

      <form id="join-form" action={~p"/join"} method="get" phx-submit="join" class="space-y-6">
        <div class="flex items-center gap-3">
          <span class="text-3xl font-semibold text-muted">#</span>
          <input
            id="join-code"
            name="event[code]"
            type="text"
            required
            maxlength="10"
            autocomplete="off"
            autocapitalize="characters"
            spellcheck="false"
            placeholder="ABCD1234"
            aria-label={gettext("Event code")}
            class="join-code-input w-full px-0 py-3 text-center text-3xl font-bold uppercase tracking-[0.28em] text-base-content"
          />
        </div>
        <button type="submit" class="btn btn-primary btn-lg w-full">{gettext("Join")}</button>
      </form>

      <div :if={@last_event} class="border-t border-line pt-6">
        <p class="text-sm text-muted">{gettext("Return to your last event")}</p>
        <.link
          href={~p"/e/#{@last_event.code}"}
          class="mt-2 inline-flex items-center gap-2 text-base font-medium text-base-content hover:text-info transition-colors"
        >
          <span>{@last_event.name}</span>
          <svg class="size-4" fill="none" stroke="currentColor" viewBox="0 0 24 24" aria-hidden="true">
            <path
              stroke-linecap="round"
              stroke-linejoin="round"
              stroke-width="2"
              d="M17 7l-10 10M8 7h9v9"
            />
          </svg>
        </.link>
      </div>
    </div>
    """
  end

  attr :error_message, :string, default: nil
  attr :oidc, :list, default: []

  defp login_form(assigns) do
    assigns =
      assign(assigns, :password_login_disabled, assigns.oidc[:disable_password_login] == true)

    ~H"""
    <div class="space-y-6">
      <h2 class="text-3xl font-bold text-base-content lg:text-4xl">{gettext("Log in")}</h2>

      <ClaperWeb.Component.Alert.error :if={@error_message} message={@error_message} />

      <.form
        :if={!@password_login_disabled}
        for={%{}}
        as={:user}
        action={~p"/users/log_in"}
        id="login-form"
        class="space-y-4"
      >
        <input type="hidden" name="remember" value="true" />
        <div>
          <label for="user_email" class="block text-sm font-medium text-base-content">
            {gettext("Email address")}
          </label>
          <input
            id="user_email"
            name="user[email]"
            type="email"
            autocomplete="username"
            required
            class="input mt-1"
          />
        </div>
        <div>
          <label for="user_password" class="block text-sm font-medium text-base-content">
            {gettext("Password")}
          </label>
          <div class="relative mt-1">
            <input
              id="user_password"
              name="user[password]"
              type="password"
              autocomplete="current-password"
              required
              class="input pr-11"
            />
            <ClaperWeb.Component.PasswordReveal.button for="user_password" />
          </div>
        </div>
        <button type="submit" class="btn btn-primary w-full">{gettext("Log in")}</button>
      </.form>

      <div :if={@oidc[:enabled]}>
        <a href={~p"/users/oidc"} class="btn btn-outline w-full">
          <img width="24" src={@oidc[:logo_url]} alt="" />
          <span>{gettext("Log in with %{provider}", provider: @oidc[:provider_name])}</span>
        </a>
      </div>

      <div
        :if={!@password_login_disabled}
        class="space-y-3 border-t border-line pt-6 text-sm text-muted"
      >
        <p>
          {link(gettext("Forgot your password?"),
            to: ~p"/users/reset_password",
            class: "font-semibold text-primary transition hover:text-primary"
          )}
        </p>
        <p :if={Application.get_env(:claper, :enable_account_creation)}>
          {gettext("Need a new account?")}
          {link(gettext("Create account"),
            to: ~p"/users/register",
            class: "font-semibold text-primary transition hover:text-primary"
          )}
        </p>
      </div>
    </div>
    """
  end
end
