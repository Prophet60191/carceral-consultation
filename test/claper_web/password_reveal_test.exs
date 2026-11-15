defmodule ClaperWeb.PasswordRevealTest do
  @moduledoc "Every password field has a show/hide button (ClaperWeb.Component.PasswordReveal)."
  use ClaperWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Claper.AccountsFixtures

  test "the sign-in form: a saved password fills in, and it can be shown", %{conn: conn} do
    page =
      conn
      |> Map.put(:remote_ip, {198, 51, 100, 242})
      |> get(~p"/users/log_in")
      |> html_response(200)

    assert page =~ ~s(autocomplete="current-password")
    assert page =~ ~s(aria-controls="user_password")
    assert page =~ "Show password"
  end

  test "My account's change-password form: new-password hints and a button on each field",
       %{conn: conn} do
    user = confirmed_user_fixture()
    {:ok, _view, html} = conn |> log_in_user(user) |> live(~p"/users/settings/edit/password")

    assert html =~ ~s(autocomplete="new-password")
    assert html =~ ~s(value="#{user.email}" autocomplete="username")
    assert length(Regex.scan(~r/data-password-reveal/, html)) >= 2
    # LiveView JS commands keep a shown password shown through redraws
    assert html =~ "data-show-js="
  end

  test "the button's commands switch the field and its own state" do
    html =
      render_component(&ClaperWeb.Component.PasswordReveal.button/1, for: "some-field")

    assert html =~ ~s(aria-controls="some-field")
    assert html =~ ~s(aria-pressed="false")
    assert html =~ "#some-field"
    assert html =~ "Hide password"
  end
end
