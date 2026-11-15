defmodule ClaperWeb.Icons do
  use Phoenix.Component

  # Interface icons drawn in the surrounding text color (currentColor), so they
  # follow the theme. They replace image files that had white baked in.
  # (Carceral Consultation, 2026-11-13; see docs/THEME.md.)

  attr :class, :string, default: "h-5 w-5"

  def send(assigns) do
    ~H"""
    <svg
      class={@class}
      xmlns="http://www.w3.org/2000/svg"
      viewBox="0 0 512 512"
      fill="currentColor"
      aria-hidden="true"
    >
      <path d="M476.59 227.05l-.16-.07L49.35 49.84A23.56 23.56 0 0027.14 52 24.65 24.65 0 0016 72.59v113.29a24 24 0 0019.52 23.57l232.93 43.07a4 4 0 010 7.86L35.53 303.45A24 24 0 0016 327v113.31A23.57 23.57 0 0026.59 460a23.94 23.94 0 0013.22 4 24.55 24.55 0 009.52-1.93L476.4 285.94l.19-.09a32 32 0 000-58.8z" />
    </svg>
    """
  end

  attr :class, :string, default: "h-5 w-5"

  def menu(assigns) do
    ~H"""
    <svg class={@class} xmlns="http://www.w3.org/2000/svg" viewBox="0 0 512 512" aria-hidden="true">
      <path
        fill="none"
        stroke="currentColor"
        stroke-linecap="round"
        stroke-miterlimit="10"
        stroke-width="32"
        d="M80 160h352M80 256h352M80 352h352"
      />
    </svg>
    """
  end

  attr :class, :string, default: "h-5 w-5"

  def exit(assigns) do
    ~H"""
    <svg class={@class} xmlns="http://www.w3.org/2000/svg" viewBox="0 0 512 512" aria-hidden="true">
      <path
        d="M320 176v-40a40 40 0 00-40-40H88a40 40 0 00-40 40v240a40 40 0 0040 40h192a40 40 0 0040-40v-40M384 176l80 80-80 80M191 256h273"
        fill="none"
        stroke="currentColor"
        stroke-linecap="round"
        stroke-linejoin="round"
        stroke-width="32"
      />
    </svg>
    """
  end

  attr :class, :string, default: "h-16 w-16"

  @doc "Envelope (outline), for 'check your email' screens."
  def envelope(assigns) do
    ~H"""
    <svg
      class={@class}
      xmlns="http://www.w3.org/2000/svg"
      fill="none"
      viewBox="0 0 24 24"
      stroke-width="1.5"
      stroke="currentColor"
      aria-hidden="true"
    >
      <path
        stroke-linecap="round"
        stroke-linejoin="round"
        d="M21.75 6.75v10.5a2.25 2.25 0 01-2.25 2.25h-15a2.25 2.25 0 01-2.25-2.25V6.75m19.5 0A2.25 2.25 0 0019.5 4.5h-15a2.25 2.25 0 00-2.25 2.25m19.5 0v.243a2.25 2.25 0 01-1.07 1.916l-7.5 4.615a2.25 2.25 0 01-2.36 0L3.32 8.91a2.25 2.25 0 01-1.07-1.916V6.75"
      />
    </svg>
    """
  end

  attr :class, :string, default: "h-24 w-24"

  @doc "Warning triangle (outline), for error pages."
  def warning(assigns) do
    ~H"""
    <svg
      class={@class}
      xmlns="http://www.w3.org/2000/svg"
      fill="none"
      viewBox="0 0 24 24"
      stroke-width="1.5"
      stroke="currentColor"
      aria-hidden="true"
    >
      <path
        stroke-linecap="round"
        stroke-linejoin="round"
        d="M12 9v3.75m-9.303 3.376c-.866 1.5.217 3.374 1.948 3.374h14.71c1.73 0 2.813-1.874 1.948-3.374L13.949 3.378c-.866-1.5-3.032-1.5-3.898 0L2.697 16.126zM12 15.75h.007v.008H12v-.008z"
      />
    </svg>
    """
  end

  attr :class, :string, default: "h-5 w-5"

  @doc "Person icon in the text color with a success-colored 'online' dot."
  def online_users(assigns) do
    ~H"""
    <svg
      class={@class}
      xmlns="http://www.w3.org/2000/svg"
      viewBox="0 0 24 24"
      fill="none"
      aria-hidden="true"
    >
      <path
        fill="currentColor"
        d="M11.9777 2.37778C6.6772 2.37778 2.19995 6.85502 2.19995 12.1556C2.19995 17.4561 6.6772 21.9333 11.9777 21.9333C17.2783 21.9333 21.7555 17.4561 21.7555 12.1556C21.7555 6.85502 17.2783 2.37778 11.9777 2.37778ZM11.9777 7.26667C13.6664 7.26667 14.9111 8.5104 14.9111 10.2C14.9111 11.8896 13.6664 13.1333 11.9777 13.1333C10.2901 13.1333 9.0444 11.8896 9.0444 10.2C9.0444 8.5104 10.2901 7.26667 11.9777 7.26667ZM6.9852 16.8215C7.86226 15.5308 9.32502 14.6704 11 14.6704H12.9555C14.6314 14.6704 16.0932 15.5308 16.9703 16.8215C15.7207 18.1591 13.948 19 11.9777 19C10.0075 19 8.2348 18.1591 6.9852 16.8215Z"
      />
      <circle cx="19.3111" cy="4.82221" r="4.4" class="fill-success" />
    </svg>
    """
  end

  def eye(assigns) do
    ~H"""
    <svg
      xmlns="http://www.w3.org/2000/svg"
      fill="none"
      viewBox="0 0 24 24"
      stroke-width="2"
      stroke="currentColor"
      class="w-5 h-5"
    >
      <path
        stroke-linecap="round"
        stroke-linejoin="round"
        d="M2.036 12.322a1.012 1.012 0 010-.639C3.423 7.51 7.36 4.5 12 4.5c4.638 0 8.573 3.007 9.963 7.178.07.207.07.431 0 .639C20.577 16.49 16.64 19.5 12 19.5c-4.638 0-8.573-3.007-9.963-7.178z"
      />
      <path stroke-linecap="round" stroke-linejoin="round" d="M15 12a3 3 0 11-6 0 3 3 0 016 0z" />
    </svg>
    """
  end

  def arrow_up(assigns) do
    ~H"""
    <svg
      class="ml-2 h-5 w-5 text-muted group-hover:text-base-content inline"
      xmlns="http://www.w3.org/2000/svg"
      viewBox="0 0 20 20"
      fill="currentColor"
    >
      <path
        fill-rule="evenodd"
        d="M5.293 7.707a1 1 0 010-1.414l4-4a1 1 0 011.414 0l4 4a1 1 0 01-1.414 1.414L11 5.414V17a1 1 0 11-2 0V5.414L6.707 7.707a1 1 0 01-1.414 0z"
        clip-rule="evenodd"
      />
    </svg>
    """
  end

  def arrow_down(assigns) do
    ~H"""
    <svg
      class="ml-2 h-5 w-5 text-muted group-hover:text-base-content inline"
      xmlns="http://www.w3.org/2000/svg"
      viewBox="0 0 20 20"
      fill="currentColor"
    >
      <path
        fill-rule="evenodd"
        d="M14.707 12.293a1 1 0 010 1.414l-4 4a1 1 0 01-1.414 0l-4-4a1 1 0 111.414-1.414L9 14.586V3a1 1 0 012 0v11.586l2.293-2.293a1 1 0 011.414 0z"
        clip-rule="evenodd"
      />
    </svg>
    """
  end
end
