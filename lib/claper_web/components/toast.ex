defmodule ClaperWeb.Toast do
  @moduledoc """
  Toasts: short messages that show for a moment (shadcn/ui "Toast",
  base-nova), replacing the filled alert bars flash messages used before
  (Jose, 2026-11-14).

    * `toaster/1` — the stack, bottom right (full width on phones); once per
      page, in the layouts. It shows the page's flash messages as toasts:
      `:info` as success (every info flash confirms something worked),
      `:success`, `:warning` and `:error` as their own types.
    * `push/3,4` — a toast from a LiveView without a page change, like
      `toast.add`: `Toast.push(socket, :success, "Copied", "The link is on
      your clipboard")`.
    * In the browser, `window.ccToast({type, title, description})`.

  Types: `:success`, `:info`, `:warning`, `:error`, `:loading` (a status icon
  each). A toast closes after about five seconds (errors after eight),
  pauses while hovered or focused, and can be closed with its × or swiped
  away (assets/js/toaster.js).
  """
  use Phoenix.Component
  use Gettext, backend: ClaperWeb.Gettext

  alias Phoenix.LiveView.JS

  @flash_types [info: :success, success: :success, warning: :warning, error: :error]

  @doc "Shows a toast on this LiveView's page now (no page change needed)."
  def push(socket, type, title, description \\ nil)
      when type in [:success, :info, :warning, :error, :loading] do
    Phoenix.LiveView.push_event(socket, "toast", %{
      type: type,
      title: title,
      description: description
    })
  end

  attr :flash, :map, default: %{}

  def toaster(assigns) do
    assigns =
      assign(
        assigns,
        :toasts,
        for {key, type} <- @flash_types,
            message = Phoenix.Flash.get(assigns.flash, key),
            is_binary(message) and message != "" do
          %{key: key, type: type, title: message, id: "toast-#{key}-#{:erlang.phash2(message)}"}
        end
      )

    ~H"""
    <section id="cc-toaster" class="toaster" aria-label={gettext("Notifications")}>
      <.toast
        :for={t <- @toasts}
        id={t.id}
        type={t.type}
        title={t.title}
        close={JS.push("lv:clear-flash", value: %{key: t.key})}
      />
    </section>
    <template id="cc-toast-template">
      <.toast id="cc-toast-proto" type={:info} title="" description="" />
    </template>
    """
  end

  attr :id, :string, required: true
  attr :type, :atom, required: true
  attr :title, :string, required: true
  attr :description, :string, default: nil
  attr :close, :any, default: nil, doc: "a JS command run when it closes (clears its flash)"

  def toast(assigns) do
    ~H"""
    <div
      id={@id}
      class="toast-card"
      data-toast
      data-type={@type}
      role={if @type == :error, do: "alert", else: "status"}
      aria-live={if @type == :error, do: "assertive", else: "polite"}
      aria-atomic="true"
      phx-update="ignore"
      data-on-close={@close}
    >
      <span class="toast-icon" aria-hidden="true">
        <.icon type={:success} />
        <.icon type={:info} />
        <.icon type={:warning} />
        <.icon type={:error} />
        <.icon type={:loading} />
      </span>
      <div class="toast-content">
        <p class="toast-title" data-toast-title>{@title}</p>
        <p :if={@description} class="toast-description" data-toast-description>
          {@description}
        </p>
      </div>
      <button
        type="button"
        class="btn btn-ghost btn-square btn-xs toast-close"
        data-toast-close
        aria-label={gettext("Close")}
      >
        <svg
          xmlns="http://www.w3.org/2000/svg"
          viewBox="0 0 24 24"
          fill="none"
          stroke="currentColor"
          stroke-width="2"
          class="size-4"
          aria-hidden="true"
        >
          <path stroke-linecap="round" stroke-linejoin="round" d="M6 18 18 6M6 6l12 12" />
        </svg>
      </button>
    </div>
    """
  end

  @icons %{
    success: "M9 12.75 11.25 15 15 9.75M21 12a9 9 0 1 1-18 0 9 9 0 0 1 18 0Z",
    info:
      "m11.25 11.25.041-.02a.75.75 0 0 1 1.063.852l-.708 2.836a.75.75 0 0 0 1.063.853l.041-.021M21 12a9 9 0 1 1-18 0 9 9 0 0 1 18 0Zm-9-3.75h.008v.008H12V8.25Z",
    warning:
      "M12 9v3.75m-9.303 3.376c-.866 1.5.217 3.374 1.948 3.374h14.71c1.73 0 2.813-1.874 1.948-3.374L13.949 3.378c-.866-1.5-3.032-1.5-3.898 0L2.697 16.126ZM12 15.75h.007v.008H12v-.008Z",
    error: "M12 9v3.75m9-.75a9 9 0 1 1-18 0 9 9 0 0 1 18 0Zm-9 3.75h.008v.008H12v-.008Z",
    loading:
      "M16.023 9.348h4.992v-.001M2.985 19.644v-4.992m0 0h4.992m-4.993 0 3.181 3.183a8.25 8.25 0 0 0 13.803-3.7M4.031 9.865a8.25 8.25 0 0 1 13.803-3.7l3.181 3.182m0-4.991v4.99"
  }

  attr :type, :atom, required: true

  defp icon(assigns) do
    assigns = assign(assigns, :d, Map.fetch!(@icons, assigns.type))

    ~H"""
    <svg
      data-toast-icon={@type}
      xmlns="http://www.w3.org/2000/svg"
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      stroke-width="1.5"
      class="size-5"
    >
      <path stroke-linecap="round" stroke-linejoin="round" d={@d} />
    </svg>
    """
  end
end
