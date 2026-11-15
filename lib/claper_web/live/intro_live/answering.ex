defmodule ClaperWeb.IntroLive.Answering do
  @moduledoc """
  Answering the intro page's interactions on a phone (docs/INTRO.md, step 8),
  run inside the event page (`ClaperWeb.EventLive.Show`), which hands over its
  `intro_*` events. The answer is built like a breakout answer
  (`ClaperWeb.BreakoutLive.Responses`) and saved with `Claper.Intro`, which
  refuses it once the event has started. Each saved answer tells the big
  screen (`:intro_answered` on the event's channel) to refresh its results.
  """
  import Phoenix.Component, only: [assign: 3]
  use Gettext, backend: ClaperWeb.Gettext

  alias Claper.Intro
  alias ClaperWeb.BreakoutLive.Responses

  @doc "The page's interaction contents and this phone's answers."
  def assign_answers(socket, page) do
    contents =
      for block <- page.blocks,
          Claper.Intro.Block.interaction?(block),
          into: %{},
          do: {block.id, Intro.load_content(block)}

    socket
    |> assign(:intro_contents, contents)
    |> assign(:intro_answers, Intro.answers_for(page, socket.assigns.attendee_identifier))
  end

  def handle_event("intro_" <> action, %{"piece" => id} = params, socket) do
    with false <- socket.assigns.started,
         true <- action in Responses.actions(),
         %{} = block <- Enum.find(socket.assigns.intro_page.blocks, &(to_string(&1.id) == id)),
         content when not is_nil(content) <- socket.assigns.intro_contents[block.id],
         current = socket.assigns.intro_answers[block.id],
         {:ok, response, opts} <- Responses.build(action, params, content, current) do
      save(socket, block, response, opts)
    else
      _ -> {:noreply, socket}
    end
  end

  def handle_event(_event, _params, socket), do: {:noreply, socket}

  defp save(socket, block, response, opts) do
    %{event: event, attendee_identifier: me, intro_page: page} = socket.assigns

    result =
      if opts[:empty?],
        do: Intro.withdraw_answer(event, block, me),
        else: Intro.put_answer(event, block, me, response)

    case result do
      ok when ok == :ok or elem(ok, 0) == :ok ->
        Phoenix.PubSub.broadcast(Claper.PubSub, "event:#{event.uuid}", :intro_answered)
        {:noreply, assign(socket, :intro_answers, Intro.answers_for(page, me))}

      {:error, message} when is_binary(message) ->
        if opts[:quiet],
          do: {:noreply, socket},
          else: {:noreply, ClaperWeb.Toast.push(socket, :error, message)}

      {:error, :started} ->
        {:noreply, socket}

      {:error, _} ->
        {:noreply, ClaperWeb.Toast.push(socket, :error, gettext("Could not save your answer"))}
    end
  end
end
