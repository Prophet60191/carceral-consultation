defmodule ClaperWeb.AdminLive.SettingsLive do
  use ClaperWeb, :admin_live_view

  alias Claper.Settings

  on_mount(ClaperWeb.UserLiveAuth)

  @impl true
  def mount(_params, session, socket) do
    with %{"locale" => locale} <- session do
      Gettext.put_locale(ClaperWeb.Gettext, locale)
    end

    socket =
      socket
      |> assign(:page_title, gettext("Settings"))
      |> load_settings()

    if admin?(socket),
      do: {:ok, socket},
      else: {:ok, redirect(socket, to: ~p"/")}
  end

  @impl true
  def handle_params(_params, _url, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_event("save", params, socket) do
    # Save transcription enabled toggle
    enabled = params["transcription_enabled"] == "true"

    ClaperWeb.AuditContext.record(socket, "admin.settings_changed",
      metadata: %{
        transcription_enabled: enabled,
        transcription_default_language: params["transcription_default_language"],
        # Never the key itself
        transcription_api_key:
          if(params["transcription_api_key"] not in [nil, ""], do: "replaced")
      }
    )

    Settings.set("transcription_enabled", if(enabled, do: "true", else: "false"))

    # Save API key only if provided (non-empty)
    api_key = params["transcription_api_key"]

    if api_key && api_key != "" do
      Settings.set_encrypted("transcription_api_key", api_key)
    end

    # Save default language (field is hidden when transcription is disabled)
    case params["transcription_default_language"] do
      nil -> :noop
      "" -> Settings.set("transcription_default_language", nil)
      language -> Settings.set("transcription_default_language", language)
    end

    {:noreply,
     socket
     |> put_flash(:info, gettext("Settings saved successfully"))
     |> load_settings()}
  end

  @impl true
  def handle_event("save_lti", params, socket) do
    value = if params["lti_enabled"] == "true", do: "true", else: "false"

    with true <- admin?(socket),
         {:ok, _} <- Settings.set("lti_enabled", value) do
      ClaperWeb.AuditContext.record(socket, "admin.settings_changed",
        metadata: %{lti_enabled: value == "true"}
      )

      {:noreply,
       socket
       |> put_flash(:info, gettext("Settings saved successfully"))
       |> load_settings()}
    else
      _ -> {:noreply, put_flash(socket, :error, gettext("Unable to save settings."))}
    end
  end

  @impl true
  def handle_event("save_security", params, socket) do
    value = if params["two_factor_required"] == "true", do: "true", else: "false"

    cond do
      not admin?(socket) ->
        {:noreply, put_flash(socket, :error, gettext("Unable to save settings."))}

      # A sign-in security change needs a recent sign-in (docs/SECURITY.md)
      not ClaperWeb.UserAuth.recently_signed_in?(socket) ->
        {:noreply,
         redirect(socket, to: ClaperWeb.UserAuth.confirm_password_path(~p"/admin/settings"))}

      true ->
        {:ok, _} = Settings.set("two_factor_required", value)

        ClaperWeb.AuditContext.record(socket, "admin.settings_changed",
          metadata: %{two_factor_required: value == "true"}
        )

        {:noreply,
         socket
         |> put_flash(:info, gettext("Settings saved successfully"))
         |> load_settings()}
    end
  end

  @impl true
  def handle_event("toggle_transcription", params, socket) do
    {:noreply, assign(socket, :transcription_enabled, params["value"] == "true")}
  end

  @impl true
  def handle_event("clear_api_key", _params, socket) do
    Settings.clear("transcription_api_key")

    ClaperWeb.AuditContext.record(socket, "admin.settings_changed",
      metadata: %{transcription_api_key: "cleared"}
    )

    {:noreply,
     socket
     |> put_flash(:info, gettext("API key cleared"))
     |> load_settings()}
  end

  defp load_settings(socket) do
    socket
    |> assign(:lti_enabled, Settings.lti_enabled?())
    |> assign(:two_factor_required, Settings.get("two_factor_required") == "true")
    |> assign(:transcription_enabled, Settings.get("transcription_enabled") == "true")
    |> assign(:api_key_configured, Settings.get_transcription_api_key() != nil)
    |> assign(:default_language, Settings.get("transcription_default_language"))
    |> assign(:languages, languages())
  end

  defp admin?(socket) do
    case socket.assigns[:current_user] do
      %Claper.Accounts.User{id: id} ->
        case Claper.Accounts.get_user(id) do
          nil -> false
          user -> Claper.Accounts.user_has_role?(user, "admin")
        end

      _ ->
        false
    end
  end

  defp languages do
    [
      {gettext("Auto-detect"), ""},
      {gettext("English"), "en"},
      {gettext("French"), "fr"},
      {gettext("German"), "de"},
      {gettext("Spanish"), "es"},
      {gettext("Italian"), "it"},
      {gettext("Portuguese"), "pt"},
      {gettext("Dutch"), "nl"},
      {gettext("Polish"), "pl"},
      {gettext("Russian"), "ru"},
      {gettext("Japanese"), "ja"},
      {gettext("Chinese"), "zh"},
      {gettext("Korean"), "ko"},
      {gettext("Arabic"), "ar"},
      {gettext("Hindi"), "hi"},
      {gettext("Turkish"), "tr"},
      {gettext("Swedish"), "sv"},
      {gettext("Norwegian"), "no"},
      {gettext("Danish"), "da"},
      {gettext("Finnish"), "fi"}
    ]
  end
end
