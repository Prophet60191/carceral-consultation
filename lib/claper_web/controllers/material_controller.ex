defmodule ClaperWeb.MaterialController do
  @moduledoc """
  The only way a handout, a take-home file or the slides' PDF leaves the
  server (docs/MATERIALS.md). Every request is checked: participants get a
  file only while it is available (`Claper.Materials.available?/3`,
  `slides_available?/2`); people who run the event always can.

  Files are sent as downloads (`Content-Disposition: attachment`, with
  `nosniff`), never shown by the browser as a page of this site; the room's
  viewer reads them with its own PDF renderer. `?download=1` (the download
  buttons) counts a download.

  Addresses use unique ids, not the event code: codes can repeat across
  ended events, and the take-home page is for ended events.
  """
  use ClaperWeb, :controller

  alias Claper.{Events, Materials, Repo}
  alias Claper.Events.Event
  alias Claper.Materials.Material

  @doc "`/materials/:id`: a handout or take-home file."
  def show(conn, %{"id" => id} = params) do
    now = NaiveDateTime.utc_now()

    with {:ok, uuid} <- Ecto.UUID.cast(id),
         %Material{} = material <- Repo.get_by(Material, uuid: uuid) |> Repo.preload(:event),
         true <-
           runs?(conn, material.event) or Materials.available?(material, material.event, now),
         path = Materials.file_path(material, material.event),
         true <- File.regular?(path) do
      if params["download"] == "1", do: Materials.record_download(material)
      send_pdf(conn, path, material.title)
    else
      _ -> not_found(conn)
    end
  end

  @doc "`/materials/slides/:event`: the slides' PDF, on the take-home page."
  def slides(conn, %{"event" => event_uuid}) do
    now = NaiveDateTime.utc_now()

    with {:ok, uuid} <- Ecto.UUID.cast(event_uuid),
         %Event{} = event <- Repo.get_by(Event, uuid: uuid),
         true <- runs?(conn, event) or Materials.slides_available?(event, now),
         path when is_binary(path) <- Materials.slides_path(event) do
      send_pdf(conn, path, event.name)
    else
      _ -> not_found(conn)
    end
  end

  defp runs?(conn, event), do: Events.can_manage?(conn.assigns[:current_user], event)

  defp send_pdf(conn, path, title) do
    conn
    |> put_resp_content_type("application/pdf", nil)
    |> put_resp_header("content-disposition", disposition(title))
    |> put_resp_header("x-content-type-options", "nosniff")
    |> put_resp_header("cache-control", "private, no-store")
    |> send_file(200, path)
  end

  # A safe file name from the title, plus its UTF-8 form for accents
  defp disposition(title) do
    ascii =
      title
      |> String.normalize(:nfd)
      |> String.replace(~r/[^A-Za-z0-9 ._-]/u, "")
      |> String.trim()
      |> case do
        "" -> "document"
        name -> String.slice(name, 0, 100)
      end

    utf8 = URI.encode(String.slice(title, 0, 100) <> ".pdf", &URI.char_unreserved?/1)
    ~s(attachment; filename="#{ascii}.pdf"; filename*=UTF-8''#{utf8})
  end

  defp not_found(conn), do: conn |> put_resp_content_type("text/plain") |> send_resp(404, "")
end
