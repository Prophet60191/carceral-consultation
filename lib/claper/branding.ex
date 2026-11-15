defmodule Claper.Branding do
  @moduledoc """
  The organization's brand, as everyone sees it: name, short mark,
  description, logo, mark, browser icon, sign-in photo and the link to this
  copy's source code. Set on the Brand page in Admin (docs/BRAND.md,
  2026-11-14) so anyone who runs the app can make it theirs without changing
  code.

  `get/0` is read on nearly every page, so the current brand is kept in
  `:persistent_term` and replaced whenever it changes. Anything not set falls
  back to a neutral default (`name/1`, `monogram/1`, `description/1`,
  `icon_src/1`, `source_url/1`).

  The app's colors are not part of the brand: they stay the design system's
  neutral roles (docs/THEME.md) so text stays readable in both themes.
  """

  import Ecto.Query, warn: false
  use Gettext, backend: ClaperWeb.Gettext

  alias Claper.Repo
  alias Claper.Branding.Brand

  @cache_key {__MODULE__, :brand}

  # Where this program's source code is published (Carceral Consultation,
  # public from 2026-11-15). The license (AGPL-3.0, section 13) asks every
  # copy to offer its source to the people using it; whoever runs a changed
  # copy sets their own on the Brand page.
  @default_source_url "https://github.com/Prophet60191/carceral-consultation"

  @default_icon "/images/default-icon.png"

  # Home screens show about this many characters under an icon.
  @short_name_max 12

  # Images: what each one is for, which files it takes, and its size limit.
  # Logo, mark and icon need a transparent background (no JPEG); SVG is never
  # accepted, since a script inside one could run on the app's own address.
  @images %{
    logo: %{field: :logo_src, types: ~w(png webp), max: 4_000_000},
    mark: %{field: :mark_src, types: ~w(png webp), max: 4_000_000},
    icon: %{field: :icon_src, types: ~w(png), max: 1_000_000},
    photo: %{field: :photo_src, types: ~w(jpg jpeg png webp), max: 8_000_000}
  }

  @doc "The current brand (never nil: an empty `%Brand{}` until one is saved)."
  def get do
    case :persistent_term.get(@cache_key, nil) do
      nil ->
        brand = Repo.one(from(b in Brand, order_by: [asc: b.id], limit: 1)) || %Brand{}
        :persistent_term.put(@cache_key, brand)
        brand

      brand ->
        brand
    end
  end

  @doc "Forgets the cached brand; the next `get/0` reads it again."
  def clear_cache do
    :persistent_term.erase(@cache_key)
    :ok
  end

  @doc "A changeset for the Brand page's form."
  def change(%Brand{} = brand, attrs \\ %{}), do: Brand.changeset(brand, attrs)

  @doc "Saves the Brand page's text fields."
  def update(attrs) do
    get()
    |> Brand.changeset(attrs)
    |> Repo.insert_or_update()
    |> refresh()
  end

  @doc "The image kinds and their rules, for the Brand page's uploads."
  def images, do: @images

  @doc "File extensions an image kind accepts, for `allow_upload/3`."
  def accept(kind), do: Enum.map(@images[kind].types, &".#{&1}")

  @doc "Largest file an image kind accepts, in bytes."
  def max_size(kind), do: @images[kind].max

  @doc """
  Stores an uploaded image for `kind` (`:logo`, `:mark`, `:icon`, `:photo`)
  and makes it the brand's. The file must really be a PNG, JPEG or WebP of an
  accepted type; the one it replaces is deleted.
  """
  def put_image(kind, tmp_path, extension) when is_map_key(@images, kind) do
    %{field: field, types: types} = @images[kind]
    ext = extension |> String.trim_leading(".") |> String.downcase()

    with true <- ext in types || {:error, :type},
         :ok <- check_contents(tmp_path, ext) do
      name = "#{Ecto.UUID.generate()}.#{ext}"
      File.mkdir_p!(dir())
      File.cp!(tmp_path, Path.join(dir(), name))
      replace_image(field, "/uploads/brand/#{name}")
    end
  end

  @doc "Removes the brand's image for `kind`; the default shows again."
  def remove_image(kind) when is_map_key(@images, kind),
    do: replace_image(@images[kind].field, nil)

  defp replace_image(field, src) do
    brand = get()
    old = Map.get(brand, field)

    result =
      brand
      |> Brand.image_changeset(field, src)
      |> Repo.insert_or_update()
      |> refresh()

    with {:ok, _} <- result, do: delete_file(old)
    result
  end

  defp refresh({:ok, brand}) do
    :persistent_term.put(@cache_key, brand)
    {:ok, brand}
  end

  defp refresh(error), do: error

  @doc "Where the brand's uploaded images (and the home-screen icons built from them) are kept."
  def images_dir,
    do: Path.join([Application.get_env(:claper, :storage_dir), "uploads", "brand"])

  defp dir, do: images_dir()

  # Only files this module stored are ever deleted.
  defp delete_file("/uploads/brand/" <> name = _src) do
    if name == Path.basename(name), do: File.rm(Path.join(dir(), name))
    :ok
  end

  defp delete_file(_), do: :ok

  # The first bytes must match the file type, so a renamed file of another
  # kind is refused.
  defp check_contents(path, ext) do
    head =
      case File.open(path, [:read, :binary], &IO.binread(&1, 12)) do
        {:ok, data} when is_binary(data) -> data
        _ -> ""
      end

    if matches?(head, ext), do: :ok, else: {:error, :contents}
  end

  defp matches?(<<0x89, "PNG", 0x0D, 0x0A, 0x1A, 0x0A, _::binary>>, "png"), do: true
  defp matches?(<<0xFF, 0xD8, 0xFF, _::binary>>, ext) when ext in ["jpg", "jpeg"], do: true
  defp matches?(<<"RIFF", _size::binary-size(4), "WEBP", _::binary>>, "webp"), do: true
  defp matches?(_, _), do: false

  # ---- What the app shows, with defaults ----

  @doc "The organization's name."
  def name(%Brand{name: name}) when is_binary(name) and name != "", do: name
  def name(%Brand{}), do: gettext("Your organization")

  @doc """
  The name under the app's icon on a phone's home screen. Phones cut off
  long names, so without one set it is the organization's name when that
  fits (#{@short_name_max} characters), otherwise the short mark.
  """
  def short_name(%Brand{short_name: short}) when is_binary(short) and short != "", do: short

  def short_name(%Brand{} = brand) do
    name = name(brand)
    if String.length(name) <= @short_name_max, do: name, else: monogram(brand)
  end

  @doc "Longest home-screen name, in characters."
  def short_name_max, do: @short_name_max

  @doc "Up to three letters for small spots: the brand's, or the name's initials."
  def monogram(%Brand{monogram: m}) when is_binary(m) and m != "", do: m

  def monogram(%Brand{} = brand) do
    brand
    |> name()
    |> String.split(~r/[^\p{L}\p{N}]+/u, trim: true)
    |> Enum.take(2)
    |> Enum.map_join(&String.first/1)
    |> String.upcase()
  end

  @doc "The short description on the sign-in pages."
  def description(%Brand{description: d}) when is_binary(d) and d != "", do: d

  def description(%Brand{}),
    do: gettext("Live presentations and workshops: your audience joins from their phones.")

  @doc "The browser tab icon."
  def icon_src(%Brand{icon_src: src}) when is_binary(src), do: src
  def icon_src(%Brand{}), do: @default_icon

  @doc "Where privacy questions and deletion requests go (the privacy page), or nil."
  def privacy_email(%Brand{privacy_email: email}) when is_binary(email) and email != "", do: email
  def privacy_email(%Brand{}), do: nil

  @doc "Where this copy's source code can be downloaded (AGPL-3.0, section 13)."
  def source_url(%Brand{source_url: url}) when is_binary(url) and url != "", do: url
  def source_url(%Brand{}), do: @default_source_url

  @doc "The address used when the brand has not set its own."
  def default_source_url, do: @default_source_url

  @doc """
  Who emails come from: `{name, address}`. The name is the server's
  `MAIL_FROM_NAME` when set, otherwise the brand's name.
  """
  def mail_from do
    mail = Application.get_env(:claper, :mail, [])

    name =
      case Keyword.get(mail, :from_name) do
        name when is_binary(name) and name != "" -> name
        _ -> name(get())
      end

    {name, Keyword.get(mail, :from)}
  end

  @doc "True once an owner has saved anything on the Brand page."
  def set_up?(%Brand{id: id}), do: not is_nil(id)
end
