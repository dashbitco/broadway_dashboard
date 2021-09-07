defmodule BroadwayDashboard.NavBarComponent do
  @moduledoc false
  # most of code copy from Phoenix.LiveDashboard.NavBarComponent
  # but this module support string for the value of nav
  use Phoenix.LiveDashboard.Web, :live_component

  @impl true
  def mount(socket) do
    {:ok, socket}
  end

  @impl true
  def update(%{page: page, items: items} = assigns, socket) do
    socket = assign(socket, assigns)
    current = current_item(page.params, items)
    {:ok, assign(socket, :current, current)}
  end

  defp current_item(params, items) do
    with %{"nav" => item} <- params,
         true <- Enum.any?(items, &match?({^item, _}, &1)) do
      item
    else
      _ -> Enum.at(items, 1) |> elem(0)
    end
  end

  def normalize_params(params) do
    case Map.fetch(params, :items) do
      :error ->
        raise ArgumentError, "the :items parameter is expected in nav bar component"

      {:ok, no_list} when not is_list(no_list) ->
        msg = ":items parameter must be a list, got: "
        raise ArgumentError, msg <> inspect(no_list)

      {:ok, items} ->
        %{
          items: Enum.into(items, %{}, &normalize_item/1),
          extra_params: normalize_extra_params(params, :nav)
        }
    end
  end

  defp normalize_extra_params(params, nav_param) do
    case Map.fetch(params, :extra_params) do
      :error ->
        []

      {:ok, extra_params_list} when is_list(extra_params_list) ->
        unless Enum.all?(extra_params_list, &is_atom/1) do
          msg = ":extra_params must be a list of atoms, got: "
          raise ArgumentError, msg <> inspect(extra_params_list)
        end

        if nav_param in extra_params_list do
          msg = ":extra_params must not contain the :nav_param field name #{inspect(nav_param)}"

          raise ArgumentError, msg
        end

        Enum.map(extra_params_list, &to_string/1)

      {:ok, extra_params} ->
        msg = ":extra_params must be a list of atoms, got: "
        raise ArgumentError, msg <> inspect(extra_params)
    end
  end

  defp normalize_item({id, item}) when is_atom(id) and is_list(item) do
    normalize_item({Atom.to_string(id), item})
  end

  defp normalize_item({id, item}) when is_binary(id) and is_list(item) do
    {id,
     item
     |> validate_item_render()
     |> validate_item_name()}
  end

  defp normalize_item(invalid_item) do
    msg = ":items must be [{string() | atom(), [name: string(), render: fun()], got: "

    raise ArgumentError, msg <> inspect(invalid_item)
  end

  defp validate_item_render(item) do
    case Keyword.fetch(item, :render) do
      :error ->
        msg = ":render parameter must be in item: #{inspect(item)}"
        raise ArgumentError, msg

      {:ok, render} when is_function(render, 0) ->
        item

      {:ok, _invalid} ->
        msg =
          ":render parameter in item must be a function that returns a component, got: #{inspect(item)}"

        raise ArgumentError, msg
    end
  end

  defp validate_item_name(item) do
    case Keyword.fetch(item, :name) do
      :error ->
        msg = ":name parameter must be in item: #{inspect(item)}"
        raise ArgumentError, msg

      {:ok, string} when is_binary(string) ->
        item

      {:ok, _invalid} ->
        msg = ":name parameter must be a string, got: #{inspect(item)}"
        raise ArgumentError, msg
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <div class="row">
        <div class="container">
          <ul class={"nav nav-pills mt-n2 mb-4"}>
            <%= for {id, item} <- @items do %>
              <li class="nav-item">
                <%= render_item_link(@socket, @page, item, @current, id, @extra_params) %>
              </li>
            <% end %>
          </ul>
        </div>
      </div>
      <%= render_content(@page, @items[@current][:render]) %>
    </div>
    """
  end

  defp render_item_link(socket, page, item, current, id, extra_params) do
    params_to_keep = for {key, value} <- page.params, key in extra_params, do: {key, value}

    path =
      Phoenix.LiveDashboard.PageBuilder.live_dashboard_path(
        socket,
        page.route,
        page.node,
        page.params,
        [{"nav", id} | params_to_keep]
      )

    class = "nav-link#{if current == id, do: " active"}"
    live_redirect(item[:name], to: path, class: class)
  end

  defp render_content(page, component_or_fun) do
    case component_or_fun do
      {component, component_assigns} ->
        live_component(component, Map.put(component_assigns, :page, page))

      fun when is_function(fun, 0) ->
        render_content(page, fun.())
    end
  end
end
