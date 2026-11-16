defmodule ClaperWeb.EventLive.Messenger do
  @moduledoc """
  The participant's messenger and theme button (Jose, 2026-11-15): one
  component, used by the intro page (before Start Event) and the live room
  (after it), so the two are the same and can't drift apart.

  The messenger is a chat bubble that opens a frosted-glass panel holding
  the event's messages (`ClaperWeb.EventLive.MessagesComponents`: the feed,
  the message box and the "post as" menu). The page owns open or closed
  (`messenger_open`, events `toggle-messenger` and `close-messenger`) and
  the red dot (`messenger_unread`); the `Messenger` hook (`assets/js/messenger.js`) closes it on a
  click outside or Escape.

  Where it sits is the stylesheet's job, keyed by `place`:

    * Computers, both places: the bottom-left corner, the theme button under
      the bubble, the panel above it.
    * `:intro`, phones and tablets: a sheet over the bottom bar.
    * `:room`, phones and tablets: the messages inline in the room
      (`inline_on_touch`), with no bubble.

  All of it is in `assets/css/messenger.css`.

  Only one messenger is ever on the page, so the fixed ids inside it
  (#chat-panel, #messenger-composer and the message system's own) stay
  unique.
  """
  use Phoenix.Component
  use Gettext, backend: ClaperWeb.Gettext

  alias ClaperWeb.EventLive.MessagesComponents

  @doc "The chat bubble and its messenger panel."
  attr :id, :string,
    required: true,
    doc: "e.g. \"intro-messenger\"; parts get -panel, -toggle, -dot"

  attr :place, :atom, values: [:intro, :room], required: true
  attr :open, :boolean, required: true
  attr :unread, :boolean, required: true

  attr :inline_on_touch, :boolean,
    default: false,
    doc: "phones and tablets show the panel's contents inline (the live room)"

  attr :class, :any, default: nil
  # The message system's data (MessagesComponents.feed/composer/identity_menu)
  attr :streams, :map, required: true
  attr :post_count, :integer, required: true
  attr :state, :map, required: true
  attr :event, :map, required: true
  attr :leaders, :list, required: true
  attr :is_leader, :boolean, required: true
  attr :current_user, :any, required: true
  attr :attendee_identifier, :any, required: true
  attr :like_posts, :list, required: true
  attr :love_posts, :list, required: true
  attr :lol_posts, :list, required: true
  attr :nickname, :any, required: true
  attr :post_changeset, :any, required: true

  def messenger(assigns) do
    ~H"""
    <div
      id={@id}
      class={["messenger", "messenger--#{@place}", @class]}
      phx-hook="Messenger"
      data-open={to_string(@open)}
    >
      <section
        id={"#{@id}-panel"}
        class="messenger-panel"
        data-messenger-panel
        aria-labelledby={"#{@id}-title"}
        inert={!@open && !@inline_on_touch}
      >
        <%!-- Phones: a handle to swipe the sheet down by --%>
        <div class="messenger-grab" aria-hidden="true"></div>
        <header class="messenger-head">
          <div class="min-w-0">
            <h2 id={"#{@id}-title"} class="text-base font-bold leading-tight">
              {gettext("Messages")}
            </h2>
            <p class="truncate text-sm text-muted">{@event.name}</p>
          </div>
          <button
            type="button"
            phx-click="close-messenger"
            aria-label={gettext("Close messages")}
            data-tooltip={gettext("Close")}
            class="btn btn-ghost btn-circle btn-sm shrink-0"
          >
            <svg
              class="size-5"
              fill="none"
              viewBox="0 0 24 24"
              stroke-width="2"
              stroke="currentColor"
              aria-hidden="true"
            >
              <path stroke-linecap="round" stroke-linejoin="round" d="M6 18 18 6M6 6l12 12" />
            </svg>
          </button>
        </header>

        <div id="chat-panel" class="messenger-feed">
          <MessagesComponents.feed
            streams={@streams}
            post_count={@post_count}
            state={@state}
            event={@event}
            leaders={@leaders}
            is_leader={@is_leader}
            current_user={@current_user}
            attendee_identifier={@attendee_identifier}
            like_posts={@like_posts}
            love_posts={@love_posts}
            lol_posts={@lol_posts}
            chip_class="messenger-chip"
          />
        </div>

        <footer id="messenger-composer" class="messenger-composer">
          <MessagesComponents.identity_menu
            state={@state}
            event={@event}
            nickname={@nickname}
            class="absolute bottom-full left-3 z-40 mb-2"
          />
          <MessagesComponents.composer
            state={@state}
            event={@event}
            nickname={@nickname}
            post_changeset={@post_changeset}
          />
        </footer>
      </section>

      <button
        id={"#{@id}-toggle"}
        type="button"
        phx-click="toggle-messenger"
        data-messenger-toggle
        aria-controls={"#{@id}-panel"}
        aria-expanded={to_string(@open)}
        aria-label={if @open, do: gettext("Close messages"), else: gettext("Open messages")}
        data-tooltip={if @open, do: gettext("Close messages"), else: gettext("Messages")}
        data-tooltip-side="right"
        class="btn btn-primary btn-circle btn-lg messenger-toggle"
      >
        <svg
          class="size-6"
          fill="none"
          viewBox="0 0 24 24"
          stroke-width="1.8"
          stroke="currentColor"
          aria-hidden="true"
        >
          <path
            stroke-linecap="round"
            stroke-linejoin="round"
            d="M8.625 12a.375.375 0 1 1-.75 0 .375.375 0 0 1 .75 0Zm4.125 0a.375.375 0 1 1-.75 0 .375.375 0 0 1 .75 0Zm4.125 0a.375.375 0 1 1-.75 0 .375.375 0 0 1 .75 0ZM2.25 12c0 4.556 4.03 8.25 9 8.25a9.764 9.764 0 0 0 2.555-.337A5.972 5.972 0 0 0 18.6 21a5.969 5.969 0 0 0 .474-2.32c1.778-1.53 2.676-3.53 2.676-5.68 0-4.556-4.03-8.25-9-8.25s-9 3.694-9 8.25Z"
          />
        </svg>
        <span :if={@unread} id={"#{@id}-dot"} class="messenger-dot">
          <span class="sr-only">{gettext("New messages")}</span>
        </span>
      </button>
    </div>
    """
  end

  @doc """
  The light/dark button: one click switches theme (`cc:set-theme`,
  `assets/js/theme.js`; remembered on the device). Its icon and label say
  where the next click goes. The page never redraws it, so the script can
  keep the label in step with the theme.
  """
  attr :id, :string, required: true, doc: "e.g. \"intro-theme\"; the button gets -toggle"
  attr :class, :any, default: nil

  def theme_button(assigns) do
    ~H"""
    <div id={@id} class={@class} phx-update="ignore">
      <button
        type="button"
        id={"#{@id}-toggle"}
        data-theme-toggle
        data-label-light={gettext("Switch to light theme")}
        data-label-dark={gettext("Switch to dark theme")}
        aria-label={gettext("Switch to light theme")}
        data-tooltip={gettext("Switch to light theme")}
        data-tooltip-side="right"
        class="btn btn-secondary btn-circle btn-lg theme-toggle"
      >
        <svg
          class="theme-icon-sun size-6"
          fill="none"
          viewBox="0 0 24 24"
          stroke-width="1.8"
          stroke="currentColor"
          aria-hidden="true"
        >
          <path
            stroke-linecap="round"
            stroke-linejoin="round"
            d="M12 3v2.25m6.364.386-1.591 1.591M21 12h-2.25m-.386 6.364-1.591-1.591M12 18.75V21m-4.773-4.227-1.591 1.591M5.25 12H3m4.227-4.773L5.636 5.636M15.75 12a3.75 3.75 0 1 1-7.5 0 3.75 3.75 0 0 1 7.5 0Z"
          />
        </svg>
        <svg
          class="theme-icon-moon size-6"
          fill="none"
          viewBox="0 0 24 24"
          stroke-width="1.8"
          stroke="currentColor"
          aria-hidden="true"
        >
          <path
            stroke-linecap="round"
            stroke-linejoin="round"
            d="M21.752 15.002A9.72 9.72 0 0 1 18 15.75c-5.385 0-9.75-4.365-9.75-9.75 0-1.33.266-2.597.748-3.752A9.753 9.753 0 0 0 3 11.25C3 16.635 7.365 21 12.75 21a9.753 9.753 0 0 0 9.002-5.998Z"
          />
        </svg>
      </button>
    </div>
    """
  end
end
