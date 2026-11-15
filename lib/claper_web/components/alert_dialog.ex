defmodule ClaperWeb.AlertDialog do
  @moduledoc """
  The app's confirmation dialog (shadcn/ui "Alert Dialog", base-nova),
  replacing the browser's own `confirm()` pop-up (Jose, 2026-11-14).

  One dialog is placed on every page by the layouts (`dialog/1`). Any
  element with `data-confirm` opens it when clicked, before the click does
  anything; "Continue" lets the click go through, "Cancel" or Esc drops it
  (assets/js/alert_dialog.js). So confirmations are written as before, with
  optional extras:

    * `data-confirm` — the description (what will happen)
    * `data-confirm-title` — the question; "Are you sure?" when left out
    * `data-confirm-action` — the confirm button; "Continue" when left out
    * `data-confirm-variant="destructive"` — for anything that can't be
      taken back: a red confirm button and a trash can
    * `data-confirm-icon="warning"` — a warning sign instead of the trash
      can, for red actions that delete nothing (Block, End event, Stop
      breakout, Revoke)

  `confirm_attrs/2` builds these for `link/2`-style `data:` lists.
  """
  use Phoenix.Component
  use Gettext, backend: ClaperWeb.Gettext

  @doc "The dialog itself; once per page, in each root layout."
  def dialog(assigns) do
    ~H"""
    <dialog
      id="cc-alert-dialog"
      class="alert-dialog"
      role="alertdialog"
      aria-modal="true"
      aria-labelledby="cc-alert-title"
      aria-describedby="cc-alert-description"
      data-default-title={gettext("Are you sure?")}
      data-default-action={gettext("Continue")}
    >
      <div class="alert-dialog-header">
        <div data-alert-media class="alert-dialog-media" hidden>
          <svg
            data-alert-icon="delete"
            xmlns="http://www.w3.org/2000/svg"
            viewBox="0 0 24 24"
            fill="none"
            stroke="currentColor"
            stroke-width="1.5"
            class="size-6"
            aria-hidden="true"
          >
            <path
              stroke-linecap="round"
              stroke-linejoin="round"
              d="m14.74 9-.346 9m-4.788 0L9.26 9m9.968-3.21c.342.052.682.107 1.022.166m-1.022-.165L18.16 19.673a2.25 2.25 0 0 1-2.244 2.077H8.084a2.25 2.25 0 0 1-2.244-2.077L4.772 5.79m14.456 0a48.108 48.108 0 0 0-3.478-.397m-12 .562c.34-.059.68-.114 1.022-.165m0 0a48.11 48.11 0 0 1 3.478-.397m7.5 0v-.916c0-1.18-.91-2.164-2.09-2.201a51.964 51.964 0 0 0-3.32 0c-1.18.037-2.09 1.022-2.09 2.201v.916m7.5 0a48.667 48.667 0 0 0-7.5 0"
            />
          </svg>
          <svg
            data-alert-icon="warning"
            xmlns="http://www.w3.org/2000/svg"
            viewBox="0 0 24 24"
            fill="none"
            stroke="currentColor"
            stroke-width="1.5"
            class="size-6"
            aria-hidden="true"
          >
            <path
              stroke-linecap="round"
              stroke-linejoin="round"
              d="M12 9v3.75m-9.303 3.376c-.866 1.5.217 3.374 1.948 3.374h14.71c1.73 0 2.813-1.874 1.948-3.374L13.949 3.378c-.866-1.5-3.032-1.5-3.898 0L2.697 16.126ZM12 15.75h.007v.008H12v-.008Z"
            />
          </svg>
        </div>
        <h2 id="cc-alert-title" class="alert-dialog-title"></h2>
        <p id="cc-alert-description" class="alert-dialog-description"></p>
      </div>
      <div class="alert-dialog-footer">
        <button type="button" class="btn btn-outline" data-alert-cancel>
          {gettext("Cancel")}
        </button>
        <button type="button" class="btn btn-primary" data-alert-action></button>
      </div>
    </dialog>
    """
  end
end
