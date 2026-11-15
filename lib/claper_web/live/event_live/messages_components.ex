defmodule ClaperWeb.EventLive.MessagesComponents do
  @moduledoc """
  The participant's message system, drawn once (2026-11-15): the feed of
  messages, the box to write one, and the "post as" menu (name or
  anonymous). The live room (`show.html.heex`, after Start Event) and the
  intro page's messenger (before it, on desktop) both use these, so they
  can't drift apart. Only one of the two is ever on the page, so the ids
  the hooks rely on (#chat-feed, #post-form, #postFormTA, #submitBtn,
  #identity-menu, #nicknamepicker) stay unique.
  """
  use Phoenix.Component
  use Gettext, backend: ClaperWeb.Gettext

  import PhoenixHTMLHelpers.Form, only: [textarea: 3]
  alias Phoenix.LiveView.JS

  @doc "The feed of messages, its empty state and the \"new messages\" pill."
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
  attr :feed_class, :any, default: nil, doc: "padding and the like, per place"
  attr :chip_class, :any, default: "bottom-20"

  def feed(assigns) do
    ~H"""
    <div
      id="chat-feed"
      class={["h-full space-y-3 overflow-y-auto overscroll-contain px-4 pt-4", @feed_class]}
      data-room-reactions={to_string(@state.message_reaction_enabled)}
      phx-update="stream"
      phx-hook="RoomFeed"
      data-chip="#new-messages-chip"
      data-posts-nb={@post_count}
    >
      <.live_component
        :for={{id, post} <- @streams.posts}
        module={ClaperWeb.EventLive.PostComponent}
        id={id}
        post={post}
        leaders={@leaders}
        is_leader={@is_leader}
        current_user={@current_user}
        attendee_identifier={@attendee_identifier}
        event={@event}
        reaction_enabled={@state.message_reaction_enabled}
        liked_posts={@like_posts}
        loved_posts={@love_posts}
        loled_posts={@lol_posts}
      />
    </div>

    <div
      :if={@post_count == 0 && @state.chat_enabled}
      class="pointer-events-none absolute inset-0 flex items-center justify-center px-8 text-center text-sm text-muted"
    >
      {gettext("Be the first to ask a question or share a thought.")}
    </div>

    <button
      id="new-messages-chip"
      type="button"
      class={["btn btn-primary btn-sm absolute left-1/2 z-20 hidden -translate-x-1/2", @chip_class]}
    >
      <span data-unread-count></span> {gettext("new messages")}&nbsp;↓
    </button>
    """
  end

  @doc "The box to write a message, or a note when messages are off."
  attr :state, :map, required: true
  attr :event, :map, required: true
  attr :nickname, :any, required: true
  attr :post_changeset, :any, required: true

  def composer(assigns) do
    ~H"""
    <%= if @state.chat_enabled do %>
      <.form
        :let={f}
        for={@post_changeset}
        id="post-form"
        class="attendee-composer flex items-center gap-1.5 rounded-2xl border border-line px-1.5 py-1 shadow-2xl"
        phx-hook="PostForm"
        data-nickname={@nickname}
        data-storage-key={"post-draft:#{@event.uuid}"}
        phx-submit="save"
      >
        <button
          id="composer-identity-button"
          type="button"
          aria-label={gettext("Choose identity")}
          phx-click={JS.toggle(to: "#identity-menu")}
          class="btn btn-secondary btn-circle btn-xs shrink-0"
        >
          {if @nickname in [nil, ""], do: "A", else: String.first(@nickname)}
        </button>

        {textarea(f, :body,
          id: "postFormTA",
          disabled: !@state.anonymous_chat_enabled && @nickname in [nil, ""],
          rows: 1,
          maxlength: 255,
          class:
            "composer-input min-h-9 max-h-16 min-w-0 flex-1 resize-none border-0 bg-transparent px-2 py-2 text-base leading-5 text-base-content outline-hidden placeholder:text-muted focus:ring-0 disabled:cursor-not-allowed disabled:opacity-50",
          placeholder:
            if(!@state.anonymous_chat_enabled && @nickname in [nil, ""],
              do: gettext("Set your nickname to participate"),
              else: gettext("Ask, comment...")
            )
        )}

        <button
          type="submit"
          id="submitBtn"
          disabled
          aria-label={gettext("Send message")}
          class="btn btn-ghost btn-circle btn-xs shrink-0"
        >
          <ClaperWeb.Icons.send />
        </button>
      </.form>
    <% else %>
      <div class="attendee-composer flex min-h-10 items-center rounded-2xl border border-line px-3 text-sm text-muted shadow-2xl">
        {gettext("Messages deactivated")}
      </div>
    <% end %>
    """
  end

  @doc "The \"post as\" menu: anonymous (when allowed) or a nickname."
  attr :state, :map, required: true
  attr :event, :map, required: true
  attr :nickname, :any, required: true
  attr :class, :any, default: "absolute bottom-16 left-2 z-40"

  def identity_menu(assigns) do
    ~H"""
    <div
      id="identity-menu"
      phx-click-away={JS.hide(to: "#identity-menu")}
      class={[
        "hidden w-64 rounded-2xl border border-line bg-base-100 p-2 text-base-content shadow-2xl",
        @class
      ]}
    >
      <p class="px-3 pb-2 pt-1 text-xs font-semibold uppercase tracking-wide text-muted">
        {gettext("Post as")}
      </p>
      <button
        :if={@state.anonymous_chat_enabled}
        id="setAnonymous"
        type="button"
        phx-click={JS.push("set-nickname") |> JS.hide(to: "#identity-menu")}
        phx-value-nickname=""
        phx-hook="EmptyNickname"
        data-storage-key={"nickname:#{@event.uuid}"}
        class="menu-item"
      >
        <span class="grid h-8 w-8 place-items-center rounded-full bg-base-300">?</span>
        <span class="font-semibold">{gettext("Anonymous")}</span>
      </button>
      <button
        :if={!@state.anonymous_chat_enabled}
        type="button"
        disabled
        class="menu-item"
        aria-disabled="true"
      >
        <span class="grid h-8 w-8 place-items-center rounded-full bg-base-300">?</span>
        <span class="font-semibold">{gettext("Anonymous")} ({gettext("disabled")})</span>
      </button>
      <button
        id="nicknamepicker"
        type="button"
        data-prompt={gettext("Enter your name")}
        data-invalid={gettext("Nickname must be between 2 and 20 characters")}
        data-close={JS.hide(to: "#identity-menu")}
        data-storage-key={"nickname:#{@event.uuid}"}
        phx-hook="NicknamePicker"
        class="menu-item"
      >
        <span class="grid h-8 w-8 place-items-center rounded-full bg-primary">
          {if @nickname in [nil, ""], do: "A", else: String.first(@nickname)}
        </span>
        <span class="min-w-0">
          <span class="block text-xs text-muted">{gettext("Nickname")}</span>
          <span class="block truncate font-semibold">
            {if @nickname in [nil, ""], do: gettext("Set your nickname"), else: @nickname}
          </span>
        </span>
      </button>
    </div>
    """
  end
end
