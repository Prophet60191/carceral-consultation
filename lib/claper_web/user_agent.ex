defmodule ClaperWeb.UserAgent do
  @moduledoc """
  A browser's user agent in words, such as "Chrome on macOS", for the
  new-device email and the Audit Log. Only a rough guess: the user agent is
  whatever the browser says, and anyone can change it.
  """
  use Gettext, backend: ClaperWeb.Gettext

  # Order matters: Edge and Opera also say "Chrome", Chrome also says "Safari"
  @browsers [
    {["Edg/", "EdgA/", "EdgiOS/", "Edge/"], "Edge"},
    {["OPR/", "Opera"], "Opera"},
    {["SamsungBrowser/"], "Samsung Internet"},
    {["Firefox/", "FxiOS/"], "Firefox"},
    {["Chrome/", "CriOS/"], "Chrome"},
    {["Safari/"], "Safari"}
  ]

  @systems [
    {["iPhone"], "iPhone"},
    {["iPad"], "iPad"},
    {["Android"], "Android"},
    {["Windows"], "Windows"},
    {["Mac OS X", "Macintosh"], "macOS"},
    {["CrOS"], "ChromeOS"},
    {["Linux"], "Linux"}
  ]

  def describe(nil), do: gettext("Unknown browser")

  def describe(user_agent) when is_binary(user_agent) do
    case {find(@browsers, user_agent), find(@systems, user_agent)} do
      {nil, nil} -> gettext("Unknown browser")
      {browser, nil} -> browser
      {nil, system} -> gettext("A browser on %{system}", system: system)
      {browser, system} -> gettext("%{browser} on %{system}", browser: browser, system: system)
    end
  end

  defp find(patterns, text) do
    Enum.find_value(patterns, fn {marks, name} -> if String.contains?(text, marks), do: name end)
  end
end
