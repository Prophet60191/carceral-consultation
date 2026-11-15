defmodule ClaperWeb.EventLive.WordCloudComponent do
  use ClaperWeb, :live_component

  @impl true
  def render(assigns) do
    assigns =
      assigns
      |> assign(:remaining, max(assigns.word_cloud.max_entries - length(assigns.entries), 0))
      |> assign(
        :own_words,
        Enum.reject(assigns.entries, &(&1.normalized_content in assigns.word_cloud.hidden_words))
      )

    ~H"""
    <div class="font-display">
      <div id="extended-word-cloud" class="w-full rounded-2xl bg-base-100 p-4 text-base-content">
        <p class="mb-1 text-xs font-semibold text-muted">{gettext("Current word cloud")}</p>
        <p class="mb-1 text-lg font-bold leading-snug text-base-content">{@word_cloud.title}</p>
        <p :if={@remaining > 0} class="mb-4 text-sm text-muted">
          {gettext("Type your own word or phrase")}
        </p>

        <form
          :if={@remaining > 0}
          id={"#{@id}-form-#{length(@entries)}"}
          phx-submit="submit-word"
          class="flex items-center gap-2"
        >
          <input
            type="text"
            name="word"
            maxlength="60"
            autocomplete="off"
            required
            placeholder={gettext("Type one word or a short phrase...")}
            class="input min-w-0 flex-1"
          />
          <button type="submit" phx-disable-with="..." class="btn btn-primary shrink-0">
            {gettext("Send")}
          </button>
        </form>

        <p :if={@remaining > 0 and @entries != []} class="mt-2 text-xs text-muted">
          {ngettext(
            "You can send one more word.",
            "You can send %{count} more words.",
            @remaining
          )}
        </p>

        <p :if={@remaining == 0} data-submitted class="text-sm text-muted">
          {gettext("Thanks! Your word has been added to the cloud.")}
        </p>

        <div :if={@own_words != []} class="mt-3 flex flex-wrap gap-1">
          <span :for={entry <- @own_words} class="badge badge-secondary badge-lg">
            {entry.content}
          </span>
        </div>

        <ClaperWeb.Component.WordCloud.cloud
          :if={@word_cloud.show_results and @words != []}
          id={"#{@id}-cloud"}
          words={@words}
          text_color="var(--color-base-content)"
          class="mt-4 py-2"
        />
      </div>
    </div>
    """
  end
end
