defmodule ClaperWeb.Component.Input do
  @moduledoc """
    Input component for forms
  """
  use ClaperWeb, :view_component
  use Gettext, backend: ClaperWeb.Gettext

  def text(assigns) do
    assigns =
      assigns
      |> assign_new(:required, fn -> false end)
      |> assign_new(:autofocus, fn -> false end)
      |> assign_new(:placeholder, fn -> false end)
      |> assign_new(:readonly, fn -> false end)
      |> assign_new(:label, fn
        %{required: false, name: name} -> ~s/#{name} #{gettext("(optional)")}/
        %{name: name} -> name
      end)
      |> assign_new(:labelClass, fn -> "text-base-content" end)
      |> assign_new(:fieldClass, fn -> "" end)
      |> assign_new(:value, fn -> input_value(assigns.form, assigns.key) end)
      |> assign_new(:minlength, fn -> nil end)
      |> assign_new(:maxlength, fn -> nil end)

    ~H"""
    <div class="relative">
      {label(@form, @key, @label, class: "block text-sm font-medium #{@labelClass}")}
      <div class="mt-1">
        {text_input(@form, @key,
          required: @required,
          readonly: @readonly,
          autofocus: @autofocus,
          placeholder: @placeholder,
          autocomplete: @key,
          value: @value,
          minlength: @minlength,
          maxlength: @maxlength,
          class: "input #{@fieldClass}"
        )}
      </div>
      <%= if Keyword.has_key?(@form.errors, @key) do %>
        <p class="text-error text-sm">{error_tag(@form, @key)}</p>
      <% end %>
    </div>
    """
  end

  def textarea(assigns) do
    assigns =
      assigns
      |> assign_new(:required, fn -> false end)
      |> assign_new(:autofocus, fn -> false end)
      |> assign_new(:placeholder, fn -> false end)
      |> assign_new(:readonly, fn -> false end)
      |> assign_new(:labelClass, fn -> "text-base-content" end)
      |> assign_new(:fieldClass, fn -> "" end)
      |> assign_new(:value, fn -> input_value(assigns.form, assigns.key) end)

    ~H"""
    <div class="relative">
      {label(@form, @key, @name, class: "block text-sm font-medium #{@labelClass}")}
      <div class="mt-1">
        {text_input(@form, @key,
          required: @required,
          readonly: @readonly,
          autofocus: @autofocus,
          placeholder: @placeholder,
          autocomplete: @key,
          value: @value,
          class: "input #{@fieldClass}"
        )}
      </div>
      <%= if Keyword.has_key?(@form.errors, @key) do %>
        <p class="text-error text-sm">{error_tag(@form, @key)}</p>
      <% end %>
    </div>
    """
  end

  def select(assigns) do
    assigns =
      assigns
      |> assign_new(:required, fn -> false end)
      |> assign_new(:autofocus, fn -> false end)
      |> assign_new(:placeholder, fn -> false end)
      |> assign_new(:labelClass, fn -> "text-base-content" end)
      |> assign_new(:fieldClass, fn -> "" end)

    ~H"""
    <div class="relative">
      {label(@form, @key, @name, class: "block text-sm font-medium #{@labelClass}")}
      <div class="mt-1">
        {select(@form, @key, @array,
          required: @required,
          autofocus: @autofocus,
          placeholder: @placeholder,
          autocomplete: @key,
          class: "select #{@fieldClass}"
        )}
      </div>
      <%= if Keyword.has_key?(@form.errors, @key) do %>
        <p class="text-error text-sm">{error_tag(@form, @key)}</p>
      <% end %>
    </div>
    """
  end

  attr :form, Phoenix.HTML.Form, required: true
  attr :key, :atom, required: true
  attr :label, :string, default: nil
  attr :labelClass, :string, default: nil

  def toggle(assigns) do
    ~H"""
    <div>
      {@label &&
        PhoenixHTMLHelpers.Form.label(@form, @key, @label,
          class: ["block text-sm font-medium", @labelClass || "text-base-content"]
        )}
      {PhoenixHTMLHelpers.Form.checkbox(@form, @key, class: "switch")}
    </div>
    """
  end

  def checked(is_checked, key, js \\ %JS{})

  def checked(false, key, js) do
    js
    |> JS.push("checked", value: %{key: key, value: true})
  end

  def checked(true, key, js) do
    js
    |> JS.remove_class("translate-x-6",
      to: "#check-#{key} > span"
    )
    |> JS.add_class("translate-x-0",
      to: "#check-#{key} > span"
    )
    |> JS.remove_class("opacity-0 ease-out duration-100",
      to: "#check-#{key} > span > span"
    )
    |> JS.add_class("opacity-100 ease-in duration-200",
      to: "#check-#{key} > span > span"
    )
    |> JS.remove_class("opacity-100 ease-in duration-200",
      to: "#check-#{key} > span > span:nth-child(2)"
    )
    |> JS.add_class("opacity-0 ease-out duration-100",
      to: "#check-#{key} > span > span:nth-child(2)"
    )
    |> JS.push("checked", value: %{key: key, value: false})
  end

  def code(assigns) do
    assigns =
      assigns
      |> assign_new(:required, fn -> false end)
      |> assign_new(:autofocus, fn -> false end)
      |> assign_new(:placeholder, fn -> false end)
      |> assign_new(:readonly, fn -> false end)
      |> assign_new(:labelClass, fn -> "text-base-content" end)
      |> assign_new(:fieldClass, fn -> "" end)

    ~H"""
    <div class="relative">
      {label(@form, @key, @name, class: "block text-sm font-bold text-base-content")}
      <div class="mt-1 relative">
        <svg
          xmlns="http://www.w3.org/2000/svg"
          width="24"
          height="24"
          viewBox="0 0 24 24"
          fill="none"
          stroke="currentColor"
          stroke-width="2"
          stroke-linecap="round"
          stroke-linejoin="round"
          class="pointer-events-none absolute left-3 top-1/2 z-10 size-4 -translate-y-1/2 text-muted"
          aria-hidden="true"
        >
          <path stroke="none" d="M0 0h24v24H0z" fill="none" />
          <path d="M5 9l14 0" />
          <path d="M5 15l14 0" />
          <path d="M11 4l-4 16" />
          <path d="M17 4l-4 16" />
        </svg>
        {text_input(@form, @key,
          required: @required,
          readonly: @readonly,
          placeholder: @placeholder,
          autofocus: @autofocus,
          autocomplete: @key,
          minlength: 5,
          maxlength: 10,
          class:
            "input pl-10 uppercase #{if Keyword.has_key?(@form.errors, @key), do: "input-error", else: ""}"
        )}
      </div>
      <%= if Keyword.has_key?(@form.errors, @key) do %>
        <p class="text-error text-sm">{error_tag(@form, @key)}</p>
      <% end %>
    </div>
    """
  end

  def date(assigns) do
    assigns =
      assigns
      |> assign_new(:required, fn -> false end)
      |> assign_new(:autofocus, fn -> false end)
      |> assign_new(:placeholder, fn -> false end)
      |> assign_new(:readonly, fn -> false end)
      |> assign_new(:locale, fn -> Gettext.get_locale(ClaperWeb.Gettext) end)
      |> assign_new(:labelClass, fn -> "text-base-content" end)
      |> assign_new(:fieldClass, fn -> "" end)

    ~H"""
    <div>
      <div class="relative" id={"#{input_id(@form, @key)}-picker"} phx-hook="DateTimeLocal">
        {label(@form, :local_date, @name, class: "block text-sm font-bold text-base-content")}
        <div class="mt-1 relative">
          {hidden_input(@form, @key)}
          {datetime_local_input(@form, :local_date,
            required: @required,
            readonly: @readonly,
            autofocus: @autofocus,
            autocomplete: "off",
            lang: @locale,
            step: 300,
            class: "input #{if Keyword.has_key?(@form.errors, @key), do: "input-error", else: ""}"
          )}
        </div>

        <%= if Keyword.has_key?(@form.errors, @key) do %>
          <p class="text-error text-sm">{error_tag(@form, @key)}</p>
        <% end %>
      </div>
    </div>
    """
  end

  def email(assigns) do
    assigns =
      assigns
      |> assign_new(:required, fn -> false end)
      |> assign_new(:autofocus, fn -> false end)
      |> assign_new(:readonly, fn -> false end)
      |> assign_new(:placeholder, fn -> false end)
      |> assign_new(:label, fn
        %{required: false, name: name} -> ~s/#{name} #{gettext("(optional)")}/
        %{name: name} -> name
      end)
      |> assign_new(:labelClass, fn -> "text-base-content" end)
      |> assign_new(:fieldClass, fn -> "" end)
      |> assign_new(:value, fn -> input_value(assigns.form, assigns.key) end)

    ~H"""
    <div class="relative">
      {label(@form, @key, @label, class: "block text-sm font-medium #{@labelClass}")}
      <div class="mt-1">
        {email_input(@form, @key,
          required: @required,
          autofocus: @autofocus,
          placeholder: @placeholder,
          readonly: @readonly,
          autocomplete: @key,
          value: @value,
          class: "input #{@fieldClass}"
        )}
      </div>
      <%= if Keyword.has_key?(@form.errors, @key) do %>
        <p class="text-error text-sm">{error_tag(@form, @key)}</p>
      <% end %>
    </div>
    """
  end

  def password(assigns) do
    assigns =
      assigns
      |> assign_new(:required, fn -> false end)
      |> assign_new(:autofocus, fn -> false end)
      |> assign_new(:placeholder, fn -> false end)
      |> assign_new(:labelClass, fn -> "text-base-content" end)
      |> assign_new(:fieldClass, fn -> "" end)
      # :new for "choose a password" (browsers suggest a strong one),
      # :current for signing in (saved passwords fill in)
      |> assign_new(:purpose, fn -> :current end)

    assigns =
      assign(assigns,
        field_attrs:
          if(assigns.purpose == :new,
            do: ClaperWeb.Component.PasswordReveal.new_password_attrs(),
            else: [autocomplete: "current-password"]
          )
      )

    ~H"""
    <div class="relative">
      {label(@form, @key, @name, class: "block text-sm font-medium #{@labelClass}")}
      <div class="relative mt-1">
        {password_input(
          @form,
          @key,
          [
            required: @required,
            autofocus: @autofocus,
            placeholder: @placeholder,
            class: "input pr-11 #{@fieldClass}"
          ] ++ @field_attrs
        )}
        <ClaperWeb.Component.PasswordReveal.button for={input_id(@form, @key)} />
      </div>
      <%= if Keyword.has_key?(@form.errors, @key) do %>
        <p class="text-error text-sm">{error_tag(@form, @key)}</p>
      <% end %>
    </div>
    """
  end
end
