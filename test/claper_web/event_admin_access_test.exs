defmodule ClaperWeb.EventAdminAccessTest do
  @moduledoc """
  Administrators can see and run every event (Jose, 2026-11-15):
  `Claper.Events.can_manage?/2` (owner, facilitator or administrator) guards
  every event screen; `get_owned_event!/3` (owner or administrator) guards
  editing, ending and deleting.
  """
  use ClaperWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Claper.{AccountsFixtures, EventsFixtures, PresentationsFixtures}

  alias Claper.{Accounts, Events, Repo}

  setup do
    for name <- ["user", "admin"] do
      _ = Accounts.get_role_by_name(name) || elem(Accounts.create_role(%{name: name}), 1)
    end

    owner = confirmed_user_fixture()
    event = event_fixture(%{user: owner})
    pf = presentation_file_fixture(%{event: event})
    presentation_state_fixture(%{presentation_file: pf})

    {:ok, admin} = Accounts.assign_role(confirmed_user_fixture(), "admin")
    facilitator = confirmed_user_fixture()
    Repo.insert!(%Events.ActivityLeader{event_id: event.id, email: facilitator.email})

    %{owner: owner, event: event, admin: admin, facilitator: facilitator}
  end

  test "who may run an event", %{owner: owner, event: event, admin: admin, facilitator: f} do
    assert Events.can_manage?(owner, event)
    assert Events.can_manage?(f, event)
    assert Events.can_manage?(admin, event)
    refute Events.can_manage?(confirmed_user_fixture(), event)
    refute Events.can_manage?(nil, event)
  end

  test "who may edit, end or delete it", %{
    owner: owner,
    event: event,
    admin: admin,
    facilitator: f
  } do
    assert Events.get_owned_event!(owner, event.uuid).id == event.id
    assert Events.get_owned_event!(admin, event.uuid).id == event.id
    assert_raise Ecto.NoResultsError, fn -> Events.get_owned_event!(f, event.uuid) end

    assert_raise Ecto.NoResultsError, fn ->
      Events.get_owned_event!(confirmed_user_fixture(), event.uuid)
    end
  end

  test "an administrator opens another person's event screens", %{
    conn: conn,
    event: event,
    admin: admin
  } do
    conn = log_in_user(conn, admin)

    for path <- [
          ~p"/e/#{event.code}/manage",
          ~p"/e/#{event.code}/presenter",
          ~p"/e/#{event.code}/intro",
          ~p"/e/#{event.code}/intro/preview",
          ~p"/e/#{event.code}/breakouts/new",
          ~p"/events/#{event.uuid}/stats",
          ~p"/events/#{event.uuid}/edit"
        ] do
      assert {:ok, _view, _html} = live(conn, path), "#{path} should open for an administrator"
    end
  end

  test "someone who is neither owner, facilitator nor administrator is still turned away",
       %{conn: conn, event: event} do
    conn = log_in_user(conn, confirmed_user_fixture())

    for path <- [~p"/e/#{event.code}/manage", ~p"/e/#{event.code}/intro"] do
      assert {:error, {:redirect, _}} = live(conn, path)
    end

    # The edit page sends them back to their own events, without the event
    assert {:error, {:redirect, %{to: "/events"}}} = live(conn, ~p"/events/#{event.uuid}/edit")
  end

  test "an administrator's edit keeps the owner", %{
    conn: conn,
    event: event,
    admin: admin,
    owner: owner
  } do
    {:ok, view, _html} = conn |> log_in_user(admin) |> live(~p"/events/#{event.uuid}/edit")

    view
    |> form("#event-form", event: %{name: "Renamed by an administrator"})
    |> render_submit()

    updated = Repo.get!(Events.Event, event.id)
    assert updated.name == "Renamed by an administrator"
    assert updated.user_id == owner.id
  end

  test "Admin › Events opens any event", %{conn: conn, event: event, admin: admin} do
    {:ok, view, _html} = conn |> log_in_user(admin) |> live(~p"/admin/events")
    assert has_element?(view, ~s(a#open-event-#{event.id}[href="/e/#{event.code}/manage"]))

    {:ok, show, _html} = conn |> log_in_user(admin) |> live(~p"/admin/events/#{event}")
    assert has_element?(show, ~s(a[href="/e/#{event.code}/manage"]), "Open event")
  end
end
