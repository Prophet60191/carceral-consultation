defmodule ClaperWeb.Notifiers.LeaderNotifier do
  use Phoenix.Swoosh, view: ClaperWeb.LeaderNotifierView, layout: {ClaperWeb.LayoutView, :email}
  use Gettext, backend: ClaperWeb.Gettext

  def event_invitation(event_name, email, url) do
    new()
    |> to(email)
    |> from(Claper.Branding.mail_from())
    |> subject(gettext("You have been invited to manage an event"))
    |> render_body("invitation.html", %{event_name: event_name, leader_email: email, url: url})
  end
end
