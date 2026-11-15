defmodule Claper.BrandingTest do
  @moduledoc "The organization's brand (docs/BRAND.md)."
  use Claper.DataCase, async: false

  alias Claper.Branding
  alias Claper.Branding.Brand

  @fixtures Path.expand("../support/fixtures/brand", __DIR__)

  setup do
    # Brand images go to a folder of their own for each test.
    previous = Application.get_env(:claper, :storage_dir)
    dir = Path.join(System.tmp_dir!(), "brand-test-#{System.unique_integer([:positive])}")
    Application.put_env(:claper, :storage_dir, dir)

    on_exit(fn ->
      Application.put_env(:claper, :storage_dir, previous)
      File.rm_rf(dir)
      Branding.clear_cache()
    end)

    %{dir: dir}
  end

  defp stored(dir, "/uploads/brand/" <> name), do: Path.join([dir, "uploads", "brand", name])

  describe "a fresh copy" do
    test "shows neutral defaults until a brand is saved" do
      brand = Branding.get()
      refute Branding.set_up?(brand)
      assert Branding.name(brand) == "Your organization"
      assert Branding.monogram(brand) == "YO"
      assert Branding.icon_src(brand) == "/images/default-icon.png"
      assert Branding.source_url(brand) == Branding.default_source_url()
      assert Branding.description(brand) =~ "joins from their phones"
      assert brand.logo_src == nil and brand.photo_src == nil
    end
  end

  describe "update/1" do
    test "saves the text and every page sees it at once" do
      assert {:ok, _} =
               Branding.update(%{
                 "name" => "  Northside Reentry Network ",
                 "description" => "Workshops by people who came home."
               })

      brand = Branding.get()
      assert Branding.set_up?(brand)
      assert Branding.name(brand) == "Northside Reentry Network"
      assert Branding.monogram(brand) == "NR"
      assert Branding.description(brand) == "Workshops by people who came home."

      assert {:ok, _} = Branding.update(%{"monogram" => "NRN"})
      assert Branding.monogram(Branding.get()) == "NRN"
      assert Branding.name(Branding.get()) == "Northside Reentry Network"
    end

    test "an emptied field goes back to its default" do
      {:ok, _} = Branding.update(%{"name" => "Northside"})
      {:ok, _} = Branding.update(%{"name" => ""})
      assert Branding.name(Branding.get()) == "Your organization"
    end

    test "refuses what doesn't fit" do
      assert {:error, changeset} = Branding.update(%{"monogram" => "ABCD"})
      assert errors_on(changeset).monogram != []

      assert {:error, changeset} = Branding.update(%{"source_url" => "javascript:alert(1)"})

      assert errors_on(changeset).source_url == [
               "Enter a full web address, starting with https://"
             ]

      assert {:error, changeset} = Branding.update(%{"photo_position" => "top"})
      assert errors_on(changeset).photo_position != []

      refute Branding.set_up?(Branding.get())
    end

    test "the source code address must be a full web address" do
      assert {:ok, _} = Branding.update(%{"source_url" => "https://example.org/our-fork"})
      assert Branding.source_url(Branding.get()) == "https://example.org/our-fork"
    end
  end

  describe "images" do
    test "a logo is stored under /uploads/brand and replaces the one before", %{dir: dir} do
      assert {:ok, brand} = Branding.put_image(:logo, Path.join(@fixtures, "logo.png"), ".png")
      assert "/uploads/brand/" <> _ = first = brand.logo_src
      assert File.exists?(stored(dir, first))
      assert Branding.get().logo_src == first

      {:ok, brand} = Branding.put_image(:logo, Path.join(@fixtures, "mark.png"), ".PNG")
      refute brand.logo_src == first
      refute File.exists?(stored(dir, first))
      assert File.exists?(stored(dir, brand.logo_src))

      {:ok, brand} = Branding.remove_image(:logo)
      assert brand.logo_src == nil
      assert Path.wildcard(Path.join([dir, "uploads", "brand", "*"])) == []
    end

    test "each image takes only its own kinds of file" do
      photo = Path.join(@fixtures, "photo.jpg")
      assert {:error, :type} = Branding.put_image(:logo, photo, ".jpg")

      assert {:ok, %Brand{photo_src: "/uploads/brand/" <> _}} =
               Branding.put_image(:photo, photo, ".jpg")

      assert {:error, :type} = Branding.put_image(:icon, Path.join(@fixtures, "logo.png"), ".svg")
    end

    test "a file renamed to look like an image is refused" do
      assert {:error, :contents} =
               Branding.put_image(:logo, Path.join(@fixtures, "fake.png"), ".png")

      assert Branding.get().logo_src == nil
    end

    test "the browser icon replaces the default" do
      {:ok, brand} = Branding.put_image(:icon, Path.join(@fixtures, "mark.png"), ".png")
      assert Branding.icon_src(brand) == brand.icon_src
    end
  end

  describe "home screen" do
    alias Claper.Branding.HomeIcon

    test "the short name is the name when it fits, otherwise the short mark" do
      {:ok, brand} = Branding.update(%{"name" => "Northside"})
      assert Branding.short_name(brand) == "Northside"

      {:ok, brand} = Branding.update(%{"name" => "Northside Reentry Network"})
      assert Branding.short_name(brand) == "NR"

      {:ok, brand} = Branding.update(%{"short_name" => "  Northside  "})
      assert Branding.short_name(brand) == "Northside"

      assert {:error, changeset} = Branding.update(%{"short_name" => String.duplicate("x", 13)})
      assert changeset.errors[:short_name]
    end

    test "the version changes with anything that shapes the icon or the manifest" do
      {:ok, brand} = Branding.update(%{"name" => "Northside", "monogram" => "NS"})
      before = HomeIcon.version(brand)
      assert HomeIcon.version(brand) == before

      {:ok, brand} = Branding.update(%{"monogram" => "NX"})
      refute HomeIcon.version(brand) == before
    end

    test "only the home-screen sizes are built" do
      assert HomeIcon.sizes() == [180, 192, 512]
      assert {:error, :size} = HomeIcon.path(Branding.get(), 64)
    end

    test "with ImageMagick: a square, solid PNG of each size, even from risky letters", %{
      dir: dir
    } do
      if Enum.any?(~w(magick convert), &System.find_executable/1) do
        {:ok, brand} = Branding.update(%{"monogram" => "@%"})

        for size <- HomeIcon.sizes() do
          assert {:ok, file} = HomeIcon.path(brand, size)
          assert String.starts_with?(file, dir)

          <<0x89, "PNG", _::binary-size(4), _::32, "IHDR", w::32, h::32, _depth, color_type,
            _::binary>> = File.read!(file)

          assert {w, h} == {size, size}
          # 2 = truecolor without alpha: nothing for a phone to fill with black
          assert color_type == 2
        end

        # A brand change leaves only the new files
        {:ok, brand} = Branding.update(%{"monogram" => "AB"})
        assert {:ok, _} = HomeIcon.path(brand, 180)
        files = File.ls!(Path.join([dir, "uploads", "brand", "home-icons"]))
        assert Enum.all?(files, &String.starts_with?(&1, HomeIcon.version(brand)))
      else
        assert {:error, :missing_imagemagick} = HomeIcon.path(Branding.get(), 180)
      end
    end
  end

  describe "mail_from/0" do
    test "emails come from the brand's name unless the server sets one" do
      previous = Application.get_env(:claper, :mail)
      on_exit(fn -> Application.put_env(:claper, :mail, previous) end)

      Application.put_env(:claper, :mail, from: "noreply@example.org", from_name: nil)
      {:ok, _} = Branding.update(%{"name" => "Northside"})
      assert Branding.mail_from() == {"Northside", "noreply@example.org"}

      Application.put_env(:claper, :mail, from: "noreply@example.org", from_name: "Workshops")
      assert Branding.mail_from() == {"Workshops", "noreply@example.org"}
    end
  end
end
