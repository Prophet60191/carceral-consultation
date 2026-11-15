defmodule ClaperWeb.TwoFactorHook do
  @moduledoc """
  Live pages' half of the two-step sign-in requirement (docs/SECURITY.md):
  someone who must use it and hasn't set it up is sent to the setup page.
  Page loads are covered by `ClaperWeb.UserAuth.require_authenticated_user/2`;
  this covers moving between live pages, which skips the plugs.
  """
  import Phoenix.LiveView
  use Phoenix.VerifiedRoutes, endpoint: ClaperWeb.Endpoint, router: ClaperWeb.Router

  alias Claper.Accounts.TwoFactor

  def on_mount(:default, _params, session, socket) do
    socket = ClaperWeb.UserAuth.mount_current_user(socket, session)
    user = socket.assigns[:current_user]

    if user && socket.view != ClaperWeb.UserSettingsLive.TwoFactor &&
         TwoFactor.setup_needed?(user) do
      {:halt,
       socket
       |> put_flash(:info, ClaperWeb.UserAuth.two_factor_setup_message())
       |> redirect(to: ~p"/users/settings/two_factor")}
    else
      {:cont, socket}
    end
  end
end
