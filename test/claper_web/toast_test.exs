defmodule ClaperWeb.ToastTest do
  @moduledoc "Toasts replace the flash alert bars (ClaperWeb.Toast; Jose, 2026-11-14)."
  use ClaperWeb.ConnCase

  import Phoenix.LiveViewTest, only: [rendered_to_string: 1]
  import Phoenix.Component, only: [sigil_H: 2]

  alias ClaperWeb.Toast

  test "flash messages become toasts: info as success, error as error" do
    assigns = %{flash: %{"info" => "Your profile has been updated.", "error" => "Could not save"}}

    html =
      rendered_to_string(~H"""
      <Toast.toaster flash={@flash} />
      """)

    assert html =~ ~s(id="cc-toaster")
    assert html =~ ~r/data-type="success"[^>]*role="status"/s
    assert html =~ "Your profile has been updated."
    assert html =~ ~r/data-type="error"[^>]*role="alert"/s
    assert html =~ "Could not save"
    # Closing a flash toast clears its flash, so it doesn't come back.
    assert html =~ "lv:clear-flash"
    # The template new toasts are cloned from.
    assert html =~ ~s(id="cc-toast-template")
  end

  test "no flash, no toasts" do
    assigns = %{}

    html =
      rendered_to_string(~H"""
      <Toast.toaster flash={%{}} />
      """)

    [stack] = Regex.run(~r{<section id="cc-toaster".*?</section>}s, html)
    refute stack =~ "data-toast"
  end

  test "a LiveView can show a toast without a page change" do
    socket = %Phoenix.LiveView.Socket{}
    socket = Toast.push(socket, :success, "Copied", "The link is on your clipboard")

    assert [["toast", %{type: :success, title: "Copied", description: description}]] =
             socket.private.live_temp.push_events

    assert description == "The link is on your clipboard"
  end

  setup :register_and_log_in_user

  test "signed-in pages carry the toaster", %{conn: conn} do
    html = conn |> get(~p"/events") |> html_response(200)
    assert html =~ ~s(id="cc-toaster")
    refute html =~ "toast toast-bottom toast-center"
  end
end
