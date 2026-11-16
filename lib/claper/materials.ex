defmodule Claper.Materials do
  @moduledoc """
  Handouts and take-home PDFs (docs/MATERIALS.md, agreed with Jose
  2026-11-15).

  An event has two lists of PDFs: **handouts**, which participants open
  during the event, and **take-home** files, on the page every phone shows
  once the event ends. Each item has its own switch. The event also says
  whether its slides are on the take-home page (`take_home_slides`) and
  until when that page is open (`take_home_until/1`).

  Files are kept in the storage directory under `materials/<event uuid>/`,
  outside the public `uploads/` folder, so they are only ever served through
  `ClaperWeb.MaterialController`, which applies `available?/3`. They are
  deleted with their item, and all of an event's with the event. Local
  storage only (this copy's setup); with S3 storage, uploads are refused.
  """
  import Ecto.Query

  alias Claper.Repo
  alias Claper.Events.Event
  alias Claper.Materials.Material

  @max_bytes 25_000_000
  @take_home_days 7

  @doc "The largest PDF accepted, in bytes (25 MB)."
  def max_bytes, do: @max_bytes

  @doc "Days the take-home page stays open after the event ends, unless set."
  def take_home_days, do: @take_home_days

  ## Reading

  @doc "An event's materials of one kind, in order."
  def list_materials(%Event{id: event_id}, kind) when kind in ["handout", "take_home"] do
    from(m in Material,
      where: m.event_id == ^event_id and m.kind == ^kind,
      order_by: [asc: m.position, asc: m.id]
    )
    |> Repo.all()
  end

  @doc "Only the ones switched on."
  def list_enabled(%Event{} = event, kind),
    do: event |> list_materials(kind) |> Enum.filter(& &1.enabled)

  @doc "A material of this event, by its public id; nil when there is none."
  def get_material(%Event{id: event_id}, uuid) do
    case Ecto.UUID.cast(uuid) do
      {:ok, uuid} -> Repo.get_by(Material, event_id: event_id, uuid: uuid)
      :error -> nil
    end
  end

  ## Adding

  @doc """
  Adds a PDF to an event's handouts or take-home list, from an uploaded file
  at `tmp_path`. `attrs` has `kind`, `title` and `original_name`. With
  `also_take_home: true` on a handout, a separate take-home copy is made too
  (its own switch). Returns `{:ok, [material]}`.
  """
  def create_material(%Event{} = event, attrs, tmp_path, opts \\ []) do
    kinds =
      case {attrs_kind(attrs), Keyword.get(opts, :also_take_home, false)} do
        {"handout", true} -> ["handout", "take_home"]
        {kind, _} -> [kind]
      end

    with :ok <- local_storage(),
         {:ok, size} <- check_pdf(tmp_path),
         {:ok, materials} <- insert_all(event, kinds, attrs, size),
         :ok <- store_files(materials, event, tmp_path) do
      broadcast(event)
      {:ok, materials}
    end
  end

  defp insert_all(event, kinds, attrs, size) do
    Repo.transaction(fn ->
      Enum.map(kinds, fn kind ->
        case insert(event, kind, attrs, size) do
          {:ok, material} -> material
          {:error, changeset} -> Repo.rollback(changeset)
        end
      end)
    end)
  end

  # The records exist; if a file can't be written, nothing is kept.
  defp store_files(materials, event, tmp_path) do
    Enum.each(materials, &store_file!(&1, event, tmp_path))
    :ok
  rescue
    _ ->
      Enum.each(materials, fn m ->
        Repo.delete(m)
        File.rm(file_path(m, event))
      end)

      {:error, :storage_failed}
  end

  defp attrs_kind(attrs), do: attrs[:kind] || attrs["kind"]

  defp insert(event, kind, attrs, size) do
    position =
      Repo.one(
        from m in Material,
          where: m.event_id == ^event.id and m.kind == ^kind,
          select: count(m.id)
      )

    %Material{event_id: event.id}
    |> Material.create_changeset(%{
      kind: kind,
      title: attrs[:title] || attrs["title"],
      original_name: attrs[:original_name] || attrs["original_name"],
      byte_size: size,
      position: position
    })
    |> Repo.insert()
  end

  @doc """
  Checks an uploaded file: a PDF (by its content, not its name) and no
  larger than `max_bytes/0`. Returns `{:ok, size}`.
  """
  def check_pdf(path) do
    with {:ok, %{size: size}} <- File.stat(path),
         true <- size > 0 || {:error, :empty},
         true <- size <= @max_bytes || {:error, :too_large},
         {:ok, head} <- read_head(path),
         true <- head == "%PDF-" || {:error, :not_pdf} do
      {:ok, size}
    else
      {:error, reason} when is_atom(reason) -> {:error, reason}
      _ -> {:error, :unreadable}
    end
  end

  defp read_head(path) do
    File.open(path, [:read, :binary], fn file -> IO.binread(file, 5) end)
    |> case do
      {:ok, head} when is_binary(head) -> {:ok, head}
      _ -> {:error, :unreadable}
    end
  end

  defp local_storage do
    storage = Application.get_env(:claper, :presentations, []) |> Keyword.get(:storage, "local")

    if storage == "local",
      do: :ok,
      else: {:error, :storage}
  end

  ## Changing

  @doc "Switches a material on or off for participants."
  # Written even when the copy at hand already says so: the switch's value
  # is what counts, not how fresh the caller's copy is.
  def set_enabled(%Material{} = material, enabled) when is_boolean(enabled) do
    material
    |> Ecto.Changeset.change()
    |> Ecto.Changeset.force_change(:enabled, enabled)
    |> Repo.update()
    |> tap(&broadcast_for/1)
  end

  @doc "Renames a material."
  def rename(%Material{} = material, title), do: change_material(material, %{title: title})

  defp change_material(material, attrs) do
    material
    |> Material.changeset(attrs)
    |> Repo.update()
    |> tap(&broadcast_for/1)
  end

  @doc "Moves a material one place up or down in its list."
  def move(%Material{} = material, direction) when direction in [:up, :down] do
    list = list_materials(%Event{id: material.event_id}, material.kind)
    index = Enum.find_index(list, &(&1.id == material.id))
    other = if direction == :up, do: index - 1, else: index + 1

    if other < 0 or other >= length(list) do
      {:ok, material}
    else
      list
      |> List.update_at(index, fn _ -> Enum.at(list, other) end)
      |> List.update_at(other, fn _ -> material end)
      |> Enum.with_index()
      |> Enum.each(fn {m, position} ->
        Repo.update_all(from(x in Material, where: x.id == ^m.id), set: [position: position])
      end)

      broadcast(%Event{id: material.event_id})
      {:ok, Repo.get!(Material, material.id)}
    end
  end

  @doc "Removes a material and its file."
  def delete_material(%Material{} = material) do
    material = Repo.preload(material, :event)

    with {:ok, deleted} <- Repo.delete(material) do
      File.rm(file_path(material, material.event))
      broadcast(material.event)
      {:ok, deleted}
    end
  end

  @doc "Counts a download (counts only; never who)."
  def record_download(%Material{id: id}) do
    from(m in Material, where: m.id == ^id) |> Repo.update_all(inc: [downloads: 1])
    :ok
  end

  ## The take-home page

  @doc "Whether the slides are on the take-home page."
  def set_take_home_slides(%Event{} = event, enabled) when is_boolean(enabled) do
    event
    |> Ecto.Changeset.change(take_home_slides: enabled)
    |> Repo.update()
    |> tap(&broadcast_for/1)
  end

  @doc """
  Sets until when the take-home page is open (naive UTC). It must be after
  the event's start.
  """
  def set_take_home_until(%Event{} = event, %NaiveDateTime{} = until) do
    until = NaiveDateTime.truncate(until, :second)

    if NaiveDateTime.compare(until, event.started_at) == :gt do
      event
      |> Ecto.Changeset.change(take_home_until: until)
      |> Repo.update()
      |> tap(&broadcast_for/1)
    else
      {:error, :before_start}
    end
  end

  @doc """
  Until when the take-home page is open: the time Jose set, or 7 days after
  the event ends. Always has a value once the event has an end; nil only
  for an event with no end yet (its page can't open before it ends anyway).
  """
  def take_home_until(%Event{take_home_until: %NaiveDateTime{} = until}), do: until
  def take_home_until(%Event{expired_at: nil}), do: nil

  def take_home_until(%Event{expired_at: ended}),
    do: NaiveDateTime.add(ended, @take_home_days * 86_400, :second)

  @doc "The event has ended and its take-home page hasn't closed yet."
  def take_home_open?(%Event{} = event, now \\ NaiveDateTime.utc_now()),
    do: ended?(event, now) and before?(now, take_home_until(event))

  @doc "The event has ended and its take-home page has closed."
  def take_home_closed?(%Event{} = event, now \\ NaiveDateTime.utc_now()),
    do: ended?(event, now) and not before?(now, take_home_until(event))

  defp ended?(%Event{expired_at: nil}, _now), do: false
  defp ended?(%Event{expired_at: ended}, now), do: NaiveDateTime.compare(now, ended) != :lt

  defp before?(_now, nil), do: false
  defp before?(now, until), do: NaiveDateTime.compare(now, until) == :lt

  @doc """
  The ended event with this code whose take-home page people are looking
  for: the most recently ended one (codes can repeat across ended events),
  or nil. Codes are compared as the app stores them (lowercase).
  """
  def ended_event_with_code(code, now \\ NaiveDateTime.utc_now()) when is_binary(code) do
    code = String.downcase(code)

    from(e in Event,
      where: e.code == ^code and not is_nil(e.expired_at) and e.expired_at <= ^now,
      order_by: [desc: e.expired_at],
      limit: 1
    )
    |> Repo.one()
  end

  @doc """
  What the take-home page offers now: the slides (when switched on and
  there is a PDF) and the take-home files switched on, in order.
  """
  def take_home_items(%Event{} = event, now \\ NaiveDateTime.utc_now()) do
    %{
      slides?: slides_available?(event, now),
      files: if(take_home_open?(event, now), do: list_enabled(event, "take_home"), else: [])
    }
  end

  @doc """
  Whether the event has a take-home page at all: the slides or a take-home
  file switched on (whether or not the page has closed since).
  """
  def take_home_configured?(%Event{take_home_slides: true}), do: true
  def take_home_configured?(%Event{} = event), do: list_enabled(event, "take_home") != []

  @doc "Whether the event has anything on its take-home page now."
  def take_home_offered?(%Event{} = event, now \\ NaiveDateTime.utc_now()) do
    case take_home_items(event, now) do
      %{slides?: true} -> true
      %{files: [_ | _]} -> true
      _ -> false
    end
  end

  ## Who may have a file

  @doc """
  Whether a participant may have this material now. A handout: switched on,
  while the event hasn't ended. A take-home file: switched on, while the
  take-home page is open. People who run the event can always have their
  files (`Claper.Events.can_manage?/2`, checked by the controller).
  """
  def available?(%Material{enabled: false}, _event, _now), do: false

  def available?(%Material{kind: "handout"}, %Event{} = event, now),
    do: not ended?(event, now)

  def available?(%Material{kind: "take_home"}, %Event{} = event, now),
    do: take_home_open?(event, now)

  @doc "Whether participants may download the slides now."
  def slides_available?(%Event{take_home_slides: true} = event, now),
    do: take_home_open?(event, now) and not is_nil(slides_path(event))

  def slides_available?(_event, _now), do: false

  ## Files

  @doc "Where a material's file is kept."
  def file_path(%Material{uuid: uuid}, %Event{uuid: event_uuid}),
    do: Path.join([storage_dir(), "materials", event_uuid, "#{uuid}.pdf"])

  @doc """
  The slides' PDF (the upload the slide images were made from), or nil when
  there is none.
  """
  def slides_path(%Event{} = event) do
    event = Repo.preload(event, :presentation_file)

    with %{hash: hash} when is_binary(hash) <- event.presentation_file,
         path = Path.join([storage_dir(), "uploads", hash, "original.pdf"]),
         true <- File.regular?(path) do
      path
    else
      _ -> nil
    end
  end

  defp store_file!(material, event, tmp_path) do
    path = file_path(material, event)
    File.mkdir_p!(Path.dirname(path))
    File.cp!(tmp_path, path)
  end

  @doc "Deletes all of an event's files (after the event is deleted)."
  def delete_event_files(%Event{uuid: uuid}) when is_binary(uuid) do
    File.rm_rf(Path.join([storage_dir(), "materials", uuid]))
    :ok
  end

  @doc """
  Copies an event's materials, files and slides switch to another event
  (duplicating an event). The take-home time is not copied: the copy's
  page closes 7 days after the copy ends.
  """
  def copy_materials(%Event{} = from, %Event{} = to) do
    copied =
      for kind <- Material.kinds(), material <- list_materials(from, kind) do
        {:ok, copy} =
          %Material{event_id: to.id}
          |> Material.create_changeset(
            Map.take(material, [:kind, :title, :original_name, :byte_size, :enabled, :position])
          )
          |> Repo.insert()

        source = file_path(material, from)
        if File.regular?(source), do: store_file!(copy, to, source)
        copy
      end

    {:ok, _} =
      to |> Ecto.Changeset.change(take_home_slides: from.take_home_slides) |> Repo.update()

    {:ok, copied}
  end

  defp storage_dir, do: Application.get_env(:claper, :storage_dir)

  ## Live updates

  @doc "Screens showing an event's materials listen here."
  def subscribe(%Event{uuid: uuid}), do: Phoenix.PubSub.subscribe(Claper.PubSub, topic(uuid))

  defp topic(uuid), do: "event:#{uuid}:materials"

  defp broadcast_for({:ok, %Material{event_id: id}}), do: broadcast(%Event{id: id})
  defp broadcast_for({:ok, %Event{} = event}), do: broadcast(event)
  defp broadcast_for(_), do: :ok

  defp broadcast(%Event{uuid: uuid}) when is_binary(uuid),
    do: Phoenix.PubSub.broadcast(Claper.PubSub, topic(uuid), :materials_changed)

  defp broadcast(%Event{id: id}) do
    case Repo.get(Event, id) do
      %Event{uuid: uuid} -> broadcast(%Event{uuid: uuid})
      nil -> :ok
    end
  end
end
