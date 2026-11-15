defmodule ClaperWeb.UserSettingsLive.Security do
  @moduledoc """
  My account › Sessions and activity (docs/SECURITY.md): where you're
  signed in (sign out any other session, or all of them), and your recent
  account activity, including changes an administrator made to it.
  """
  use ClaperWeb, :live_view

  alias Claper.Accounts.Sessions
  alias ClaperWeb.ActivityText

  on_mount(ClaperWeb.UserLiveAuth)
  on_mount(ClaperWeb.ReturnContextHook)

  @impl true
  def mount(_params, session, socket) do
    with %{"locale" => locale} <- session do
      Gettext.put_locale(ClaperWeb.Gettext, locale)
    end

    {:ok,
     socket
     |> assign(:page_title, gettext("Sessions and activity"))
     # Server-side only: tells this browser's session apart from the others
     |> assign(:session_token, session["user_token"])
     |> load()}
  end

  defp load(socket) do
    user = socket.assigns.current_user

    socket
    |> assign(:sessions, Sessions.list(user, socket.assigns.session_token))
    |> assign(:activity, Claper.Audit.list_account_activity(user))
  end

  @impl true
  def handle_event("sign_out_session", %{"id" => id}, socket) do
    case Sessions.sign_out(socket.assigns.current_user, id, socket.assigns.session_token) do
      :ok ->
        ClaperWeb.AuditContext.record(socket, "user.session_signed_out",
          resource: {"session", String.to_integer(to_string(id))}
        )

        {:noreply, socket |> load() |> put_flash(:info, gettext("That session is signed out."))}

      :error ->
        {:noreply,
         socket |> load() |> put_flash(:error, gettext("That session was already gone."))}
    end
  end

  def handle_event("sign_out_others", _params, socket) do
    {:ok, count} =
      Sessions.sign_out_others(socket.assigns.current_user, socket.assigns.session_token)

    ClaperWeb.AuditContext.record(socket, "user.other_sessions_signed_out",
      metadata: %{sessions: count}
    )

    {:noreply,
     socket
     |> load()
     |> put_flash(
       :info,
       ngettext("1 other session signed out.", "%{count} other sessions signed out.", count)
     )}
  end

  def when_text(%NaiveDateTime{} = at), do: Calendar.strftime(at, "%-d %b %Y, %H:%M UTC")
  def when_text(%DateTime{} = at), do: Calendar.strftime(at, "%-d %b %Y, %H:%M UTC")

  defdelegate describe(log), to: ActivityText
  defdelegate origin(log), to: ActivityText
end
