defmodule ClaperWeb.Plugs.PrivateUploads do
  @moduledoc """
  Keeps a presentation's original upload (`/uploads/<hash>/original.pdf`,
  `.pptx`…) from being served as a public file (2026-11-15). The slide
  images beside it are public, so the folder's address is known to every
  participant; the original is only handed out through the take-home page,
  when the presenter allows it (`ClaperWeb.MaterialController.slides/2`).

  Sits in the endpoint just before the `/uploads` static files.
  """
  import Plug.Conn

  def init(opts), do: opts

  def call(%Plug.Conn{path_info: ["uploads", _folder, "original." <> _ext]} = conn, _opts) do
    conn |> send_resp(404, "") |> halt()
  end

  def call(conn, _opts), do: conn
end
