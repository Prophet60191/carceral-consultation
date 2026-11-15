defmodule Claper.Branding.HomeIcon do
  @moduledoc """
  The app's icon on a phone's home screen (Jose, 2026-11-15).

  Phones want a large, square, solid icon: iPhones fill a transparent one
  with black, and the browser icon (`Claper.Branding.icon_src/1`) is often
  only 64 pixels, which turns blurry at home-screen sizes. So each size is
  built from the brand:

  - the uploaded browser icon, when it is at least #{180} pixels on its short
    side, fitted onto the theme's page color; otherwise
  - the brand's short mark (`Claper.Branding.monogram/1`) drawn sharp in the
    app's type (Roboto Medium), in the theme's text color on its page color.

  Files are built with ImageMagick (already in the runtime image for slides)
  on first request and kept under `uploads/brand/home-icons/`, named after a
  `version/1` of everything that shapes them, so a brand change makes new
  files and the old ones are removed. Without ImageMagick, `path/2` returns
  an error and the caller falls back to the browser icon as it is.
  """
  alias Claper.Branding
  alias Claper.Branding.Brand

  @sizes [180, 192, 512]
  @min_image_side 180
  @commands ~w(magick convert convert-im6.q16)
  # Bump when the way icons are drawn changes, so cached files are rebuilt.
  @recipe 1

  @doc "The sizes that can be built (iPhone 180; manifest 192 and 512)."
  def sizes, do: @sizes

  @doc """
  A short fingerprint of everything that shapes the icons and the manifest:
  it goes into file names and into `?v=` on their links, so phones fetch the
  new ones after a brand change.
  """
  def version(%Brand{} = brand) do
    {@recipe, brand.icon_src, Branding.monogram(brand), Branding.name(brand),
     Branding.short_name(brand), colors()}
    |> :erlang.term_to_binary()
    |> then(&:crypto.hash(:sha256, &1))
    |> Base.url_encode64(padding: false)
    |> binary_part(0, 12)
  end

  @doc "The icon file for `size`, building it first if needed."
  def path(%Brand{} = brand, size) when size in @sizes do
    file = Path.join(dir(), "#{version(brand)}-#{size}.png")

    if File.regular?(file), do: {:ok, file}, else: build(brand, size, file)
  end

  def path(%Brand{}, _size), do: {:error, :size}

  defp build(brand, size, file) do
    tmp = "#{file}.#{System.unique_integer([:positive])}.tmp"

    with {:ok, command} <- command(),
         :ok <- File.mkdir_p(dir()),
         {_, 0} <- System.cmd(command, args(brand, size, tmp), stderr_to_stdout: true),
         :ok <- File.rename(tmp, file) do
      prune(brand)
      {:ok, file}
    else
      {:error, _} = error ->
        File.rm(tmp)
        error

      {output, status} ->
        File.rm(tmp)
        {:error, {:imagemagick, status, output}}
    end
  end

  # Both drawings end in "PNG24:" so the file has no transparency at all.
  defp args(brand, size, out) do
    {page, text} = colors()
    canvas = ["-size", "#{size}x#{size}", "xc:#{page}"]

    case large_icon(brand) do
      {:ok, source} ->
        canvas ++
          [source, "-resize", "#{size}x#{size}", "-gravity", "center", "-composite"] ++
          ["PNG24:#{out}"]

      :none ->
        letters = Branding.monogram(brand)

        canvas ++
          ["-font", font(), "-fill", text, "-gravity", "center"] ++
          ["-pointsize", "#{point_size(letters, size)}"] ++
          ["-annotate", "+0+#{round(size * 0.011)}", escape(letters), "PNG24:#{out}"]
    end
  end

  # One letter fills more of the tile than three.
  defp point_size(letters, size) do
    scale =
      case String.length(letters) do
        1 -> 0.56
        2 -> 0.44
        _ -> 0.33
      end

    round(size * scale)
  end

  # ImageMagick reads text starting with "@" as a file name and expands
  # "%" sequences; the short mark is plain text, so neither may apply.
  defp escape(text) do
    text
    |> String.replace("\\", "\\\\")
    |> String.replace("%", "%%")
    |> then(fn
      "@" <> rest -> "\\@" <> rest
      other -> other
    end)
  end

  # The uploaded browser icon, when it is big enough to look sharp.
  defp large_icon(%Brand{icon_src: "/uploads/brand/" <> name}) when is_binary(name) do
    file = Path.join(Branding.images_dir(), name)

    with true <- name == Path.basename(name),
         {:ok, {width, height}} <- png_size(file),
         true <- min(width, height) >= @min_image_side do
      {:ok, file}
    else
      _ -> :none
    end
  end

  defp large_icon(%Brand{}), do: :none

  # Width and height from the PNG header (the first chunk is always IHDR).
  defp png_size(file) do
    case File.open(file, [:read, :binary], &IO.binread(&1, 24)) do
      {:ok, <<0x89, "PNG", 0x0D, 0x0A, 0x1A, 0x0A, _len::32, "IHDR", width::32, height::32>>} ->
        {:ok, {width, height}}

      _ ->
        :error
    end
  end

  # Only this brand's current files stay.
  defp prune(brand) do
    current = version(brand)

    case File.ls(dir()) do
      {:ok, names} ->
        for name <- names,
            not String.starts_with?(name, current <> "-"),
            do: File.rm(Path.join(dir(), name))

        :ok

      _ ->
        :ok
    end
  end

  defp command do
    case Enum.find(@commands, &System.find_executable/1) do
      nil -> {:error, :missing_imagemagick}
      command -> {:ok, command}
    end
  end

  # The theme's page and text colors (a PNG cannot read the stylesheet; the
  # literal values live in ClaperWeb.Theme and are checked against it).
  defp colors, do: {ClaperWeb.Theme.email(:page), ClaperWeb.Theme.email(:text)}

  defp font,
    do: Application.app_dir(:claper, "priv/static/fonts/Roboto/roboto-v29-latin-500.ttf")

  defp dir, do: Path.join(Branding.images_dir(), "home-icons")
end
