defmodule ClaperWeb.EventLive.EmbedIframeComponent do
  use ClaperWeb, :live_component

  alias Claper.Embeds.Embed

  def render(assigns) do
    iframe_attrs =
      if assigns.provider == "custom" do
        case Embed.custom_iframe_attributes(assigns.content) do
          {:ok, attrs} -> attrs
          :error -> nil
        end
      end

    # Stored links are re-validated: rows may predate host validation.
    provider_url =
      case Embed.provider_embed_url(assigns.provider, assigns.content) do
        {:ok, url} -> url
        :error -> nil
      end

    assigns = assign(assigns, iframe_attrs: iframe_attrs, provider_url: provider_url)

    ~H"""
    <div id={@id} class="h-full w-full">
      <%= case @provider do %>
        <% "youtube" -> %>
          <iframe
            :if={@provider_url}
            class="h-full w-full"
            title={@title}
            src={@provider_url}
            frameborder="0"
            allow="accelerometer; autoplay; clipboard-write; encrypted-media; gyroscope; picture-in-picture; web-share"
            referrerpolicy="strict-origin-when-cross-origin"
            allowfullscreen
          >
          </iframe>
        <% "vimeo" -> %>
          <iframe
            :if={@provider_url}
            class="h-full w-full"
            title={@title}
            src={@provider_url}
            frameborder="0"
            allow="autoplay; fullscreen; picture-in-picture"
            allowfullscreen
          >
          </iframe>
        <% provider when provider in ["canva", "googleslides"] -> %>
          <iframe
            :if={@provider_url}
            class="h-full w-full"
            title={@title}
            src={@provider_url}
            frameborder="0"
            allowfullscreen="allowfullscreen"
            allow="fullscreen"
          >
          </iframe>
        <% "website" -> %>
          <%!-- Any web page, in a sandboxed frame: it may run its own scripts
               and open links in new tabs, but cannot take over this app's tab.
               No referrer, so sites don't see this app's address. Many sites
               refuse frames, so the button to open it in a new tab is always
               there. --%>
          <div :if={@provider_url} class="flex h-full w-full flex-col">
            <div class="flex shrink-0 items-center justify-between gap-3 bg-base-200 px-3 py-1.5">
              <span class="min-w-0 truncate text-sm text-muted">{URI.parse(@provider_url).host}</span>
              <a
                href={@provider_url}
                target="_blank"
                rel="noopener noreferrer"
                class="btn btn-outline btn-sm shrink-0"
              >
                <svg class="size-4" viewBox="0 0 20 20" fill="currentColor" aria-hidden="true">
                  <path d="M11 3a1 1 0 1 0 0 2h2.586l-6.293 6.293a1 1 0 1 0 1.414 1.414L15 6.414V9a1 1 0 1 0 2 0V4a1 1 0 0 0-1-1h-5Z" />
                  <path d="M5 5a2 2 0 0 0-2 2v8a2 2 0 0 0 2 2h8a2 2 0 0 0 2-2v-3a1 1 0 1 0-2 0v3H5V7h3a1 1 0 0 0 0-2H5Z" />
                </svg>
                {gettext("Open in a new tab")}
              </a>
            </div>
            <iframe
              class="min-h-0 w-full flex-1 bg-stage"
              title={@title}
              src={@provider_url}
              frameborder="0"
              sandbox="allow-scripts allow-same-origin allow-forms allow-popups allow-popups-to-escape-sandbox allow-presentation"
              referrerpolicy="no-referrer"
              allow="fullscreen"
              allowfullscreen
            >
            </iframe>
          </div>
        <% "custom" -> %>
          <iframe :if={@iframe_attrs} {@iframe_attrs}></iframe>
      <% end %>
    </div>
    """
  end
end
