defmodule ClaperWeb.BrandPanel do
  @moduledoc """
  The left-hand panel on the sign-in and account pages (log in, sign up,
  forgot / reset password, confirm email): the brand's photo, name and
  description, all from the Brand page (`Claper.Branding`, docs/BRAND.md).
  One copy, used by every page.

  With a photo, the panel is always dark (the photo is darkened under the
  text so it stays readable); without one, it is a plain panel in the
  current theme.
  """
  use Phoenix.Component
  use Gettext, backend: ClaperWeb.Gettext

  alias Claper.Branding

  # Which part of the photo stays in view: on phones the banner is wide and
  # short, on larger screens the panel is tall.
  @phone_position %{
    "left" => "bg-[left_35%]",
    "center" => "bg-[center_35%]",
    "right" => "bg-[right_35%]"
  }
  @panel_position %{"left" => "bg-left", "center" => "bg-center", "right" => "bg-right"}

  # The license notices and source code (AGPL-3.0, section 13)
  attr :class, :string, default: nil

  defp about_link(assigns) do
    ~H"""
    <p class={["text-sm", @class]}>
      <a href="/about" class="text-muted underline-offset-4 hover:text-base-content hover:underline">
        {gettext("About this app")}
      </a>
    </p>
    """
  end

  def panel(assigns) do
    brand = Branding.get()
    position = brand.photo_position || "center"

    assigns =
      assign(assigns,
        photo: brand.photo_src,
        phone_position: Map.get(@phone_position, position, "bg-center"),
        panel_position: Map.get(@panel_position, position, "bg-center"),
        description: Branding.description(brand)
      )

    ~H"""
    <%!-- Phone: the photo as a banner with the name over it, the description
         below, then the page's form (the layout stacks them). --%>
    <div class="md:hidden" data-theme={@photo && "carceral"}>
      <div
        :if={@photo}
        class={["relative h-64 bg-cover flex items-end p-5", @phone_position]}
        style={"background-image: url('#{@photo}');"}
      >
        <div class="absolute inset-0 bg-linear-to-t from-scrim/85 via-scrim/30 to-transparent"></div>
        <ClaperWeb.Wordmark.mark size={:lg} class="relative z-10 text-base-content" />
      </div>
      <div :if={!@photo} class="flex items-end bg-base-200 px-5 pt-8 pb-2">
        <ClaperWeb.Wordmark.mark size={:lg} class="text-base-content" />
      </div>
      <p class="px-5 pt-4 text-sm leading-6 text-muted">{@description}</p>
      <.about_link class="px-5 pt-2" />
    </div>

    <%!-- Tablet and computer: the photo panel beside the form. --%>
    <div
      data-theme={@photo && "carceral"}
      class={[
        "hidden md:flex md:w-1/2 xl:w-3/5 flex-auto items-end justify-start overflow-hidden p-10 text-base-content relative",
        @photo && ["bg-cover", @panel_position],
        !@photo && "bg-base-200 border-r border-line"
      ]}
      style={@photo && "background-image: url('#{@photo}');"}
    >
      <%!-- The text keeps to the left; only the lower left is darkened so it
           stays readable over the photo. --%>
      <div
        :if={@photo}
        class="absolute inset-0 bg-linear-to-tr from-scrim/90 via-scrim/45 to-transparent"
      >
      </div>
      <div class="relative z-10 w-[55%] space-y-5">
        <ClaperWeb.Wordmark.mark
          size={:none}
          class="w-full text-base-content [--wm-h:clamp(2rem,4vw,4rem)]"
        />
        <p class="text-base leading-7 text-base-content lg:text-lg lg:leading-8">
          {@description}
        </p>
        <.about_link />
      </div>
    </div>
    """
  end
end
