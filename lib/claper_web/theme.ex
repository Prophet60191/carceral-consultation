defmodule ClaperWeb.Theme do
  @moduledoc """
  Theme helpers for Carceral Consultation (2026-11-13).

  All colors are defined once, in `assets/css/theme-config.css`. Code that has
  to choose a color picks a theme role (a Tailwind class such as `bg-base-300`)
  from here instead of writing a color value. See `docs/THEME.md`.

  The one exception is email: mail programs cannot read the app's stylesheet,
  so `email/1` holds the same theme colors as literal values. The home-screen
  icon (`Claper.Branding.HomeIcon`) is drawn with the same values, and so is
  the manifest's background, for the same reason. Keep them equal
  to theme-config.css; `scripts/theme/check_theme.sh` checks that they match.
  """

  # Avatar backgrounds: three charcoal surfaces. The emoji on top tells
  # attendees apart; the shade only adds a little variety.
  @avatar_classes ["bg-base-300", "bg-base-400", "bg-selected"]

  @doc "Theme background class for an attendee avatar, stable for the same identifier."
  def avatar_class(identifier) do
    Enum.at(@avatar_classes, :erlang.phash2(identifier, length(@avatar_classes)))
  end

  # Email colors, mirrored from theme-config.css (role => value).
  @email %{
    page: "#121214",
    card: "#1b1b1e",
    raised: "#252528",
    text: "#ededef",
    muted: "#a1a1aa",
    line: "#2e2e33",
    button: "#f2f2f3",
    button_text: "#121214",
    shadow: "rgba(0, 0, 0, 0.3)"
  }

  @doc "Literal theme color for email templates, e.g. `email(:text)`."
  def email(role), do: Map.fetch!(@email, role)
end
