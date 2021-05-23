defmodule BroadwayDashboard.LiveDashboard.LayeredGraphComponent do
  use Phoenix.LiveDashboard.Web, :live_component

  @moduledoc """
  A component for drawing layered graphs.

  This is useful to represent pipelines like we have on
  [BroadwayDashboard](https://hexdocs.pm/broadway_dashboard) where
  each layer points to nodes of the layer below.
  It draws the layers from top to bottom.

  The calculation of layers and positions is done automatically
  based on options.

  ## Options

    * `:title` - The title of the component. Default: `nil`.

    * `:hint` - A textual hint to show close to the title. Default: `nil`.

    * `:layers` - A graph of layers with nodes. They represent
      our graph structure (see example). Each layer is a list
      of nodes, where each node has the following fields:

      - `:id` - The ID of the given node.
      - `:children` - The IDs of children nodes.
      - `:data` - A string or a map. If it's a map, the required fields
        are `detail` and `label`.

    * `:show_grid?` - Enable or disable the display of a grid. This
      is useful for development. Default: `false`.

    * `:y_label_offset` - The offset of label position relative to the
      center of its circle in the Y axis. Default: `5`.

    * `:y_detail_offset` - The offset of detail position relative to the
      center of its circle in the Y axis. Default: `18`.

  ## Examples

      iex> layers = [
      ...>   [
      ...>     %{
      ...>       id: MyPipeline.Broadway.Producer_0,
      ...>       data: %{
      ...>         detail: 0,
      ...>         label: "prod_0"
      ...>       },
      ...>       children: [MyPipeline.Broadway.Processor_default_0]
      ...>     }
      ...>   ],
      ...>   [
      ...>     %{
      ...>       id: MyPipeline.Broadway.Processor_default_0,
      ...>       data: %{
      ...>         detail: 0,
      ...>         label: "proc_1"
      ...>       },
      ...>       children: []
      ...>      }
      ...>    ]
      ...> ]
      iex> layered_graph(layers: layers, title: "Pipeline", hint: "A pipeline")
  """

  @type node_data :: binary() | %{label: binary(), detail: term()}
  @type node_id :: term()
  @type layer_node :: %{id: node_id(), children: [node_id()], data: node_data()}
  @type layer :: [layer_node()]
  @type layers :: [layer()]

  @max_diameter 80

  defmodule Arrow do
    @moduledoc false

    defstruct [:x1, :y1, :x2, :y2]
  end

  defmodule Circle do
    @moduledoc false

    defstruct [:id, :x, :y, :label, :detail, :show_detail?, :bg, :children]
  end

  @impl true
  def mount(socket) do
    {:ok, socket}
  end

  @impl true
  def render(assigns) do
    layers = assigns.layers

    # Note that the view box can change dynamically based on the size of layers.
    opts = %{
      view_box_width: 1000,
      view_box_height: 1000,
      max_nodes_before_scale_up: 10,
      node_diameter_for_scale_up: 100,
      scale_up: false,
      x_gap: 0.2,
      y_gap: 1.0,
      show_grid?: Map.get(assigns, :show_grid?, false),
      y_label_offset: Map.get(assigns, :y_label_offset, 5),
      y_detail_offset: Map.get(assigns, :y_detail_offset, 18)
    }

    {circles, arrows, opts} = build(layers, opts)

    ~L"""
    <%= if @title do %>
      <h5 class="card-title">
        <%= @title %>
        <%= if @hint do %>
          <%= hint(do: @hint) %>
        <% end %>
      </h5>
    <% end %>
    <div class="card">
      <div class="card-body card-graph broadway-dashboard" style="overflow-x: auto;">
      <svg
        xmlns="http://www.w3.org/2000/svg"
        viewBox="0 0 <%= opts.view_box_width%> <%= opts.view_box_height %>"
        style="width: <%= if opts.scale_up, do: opts.scale_up, else: 100 %>%;">
          <style>
            .graph-line {
              stroke: #dae0ee;
              fill: #dae0ee;
              stroke-width: 1;
            }

            .graph-circle-label, .graph-circle-detail {
              fill: #fff;
              font-family: 'LiveDashboardFont';
            }
          </style>
          <defs>
            <marker id="arrow" markerWidth="10" markerHeight="10" refX="0" refY="3" orient="auto" markerUnits="strokeWidth">
              <path d="M0,0 L0,6 L9,3 z" class="graph-line" />
            </marker>
            <pattern id="smallGrid" width="10" height="10" patternUnits="userSpaceOnUse">
              <path d="M 10 0 L 0 0 0 10" fill="none" stroke="gray" stroke-width="0.5" />
            </pattern>
            <pattern id="grid" width="100" height="100" patternUnits="userSpaceOnUse">
              <rect width="100" height="100" fill="url(#smallGrid)" />
              <path d="M 100 0 L 0 0 0 100" fill="none" stroke="gray" stroke-width="1" />
            </pattern>
          </defs>

          <rect width="<%= if opts.show_grid?, do: "100%", else: 0 %>" height="100%" fill="url(#grid)" />

          <%= for arrow <- arrows do %>
            <line x1="<%= arrow.x1 %>" y1="<%= arrow.y1 %>" x2="<%= arrow.x2 %>" y2="<%= arrow.y2 %>" class="graph-line" marker-end="url(#arrow)"/>
          <% end %>
          <%= for circle <- circles do %>
           <g>
            <circle fill="<%= circle.bg %>" cx="<%= circle.x %>" cy="<%= circle.y %>" r="<%= opts.r %>" class="graph-circle" />
            <%= if circle.show_detail? do %>
              <text text-anchor="middle" x="<%= circle.x %>" y="<%= circle.y %>" class="graph-circle-label"><%= circle.label %></text>
              <text text-anchor="middle" x="<%= circle.x %>" y="<%= circle.y + opts.y_detail_offset %>" class="graph-circle-detail"><%= circle.detail %></text>
            <% else %>
              <text text-anchor="middle" x="<%= circle.x %>" y="<%= circle.y + opts.y_label_offset %>" class="graph-circle-label"><%= circle.label %></text>
            <% end %>
           </g>
          <% end %>
        </svg>
      </div>
    </div>
    """
  end

  defp build(layers, opts) do
    max_nodes = Enum.max(Enum.map(layers, &length/1))

    opts = maybe_scale_width_up(max_nodes, opts)

    diameter = opts.view_box_width / (max_nodes + (max_nodes - 1) * opts.x_gap)

    diameter = min(diameter, @max_diameter)

    radius = diameter / 2

    gap = diameter * opts.x_gap

    opts =
      opts
      |> Map.put_new(:d, diameter)
      |> Map.put_new(:r, radius)
      |> Map.put_new(:gap, gap)
      |> Map.put_new(:groups_gap, gap * 3)

    layers =
      layers
      |> Enum.with_index()
      |> Enum.map(fn {layer, index} ->
        groups = group_nodes_by_children(layer, opts)

        %{
          index: index,
          group_size: length(groups),
          groups: groups
        }
      end)
      |> adjust_child_layers_in_groups()
      |> calculate_layers_positions(opts)

    circles =
      for layer <- layers,
          group <- layer.groups,
          node <- group.nodes,
          do: circle(node, opts)

    circles_map = circles |> Enum.map(fn circle -> {circle.id, circle} end) |> Map.new()

    arrows =
      Enum.flat_map(circles, fn circle ->
        Enum.map(circle.children, fn child_id ->
          child = Map.fetch!(circles_map, child_id)
          arrow({circle.x, circle.y}, {child.x, child.y}, opts)
        end)
      end)

    opts = adjust_view_box_height(layers, opts)

    {circles, arrows, opts}
  end

  defp maybe_scale_width_up(max_nodes, opts) do
    if max_nodes > opts.max_nodes_before_scale_up do
      extra_nodes = max_nodes - opts.max_nodes_before_scale_up
      new_view_box = opts.view_box_width + extra_nodes * opts.node_diameter_for_scale_up

      opts
      |> Map.put(:view_box_width, new_view_box)
      |> Map.put(:scale_up, new_view_box * 100 / opts.view_box_width)
    else
      opts
    end
  end

  defp adjust_view_box_height(layers, opts) do
    max_layer_y = Enum.map(layers, & &1.start_y) |> Enum.max()

    bottom_end = max_layer_y + opts.d * (opts.y_gap + 0.2)

    if bottom_end != opts.view_box_height do
      Map.put(opts, :view_box_height, bottom_end)
    else
      opts
    end
  end

  defp group_nodes_by_children(layer, _opts) do
    layer
    |> Enum.chunk_by(&Enum.sort(&1.children))
    |> Enum.with_index()
    |> Enum.map(fn {group, group_index} ->
      [member | _] = group

      %{
        index: group_index,
        nodes: group,
        children: member.children
      }
    end)
  end

  defp adjust_child_layers_in_groups(layers) do
    pairs = Enum.chunk_every(layers, 2)

    Enum.flat_map(pairs, fn
      [parent, child] = pair ->
        if parent.group_size > 1 && child.group_size == 1 do
          parent_uniq_groups = Enum.uniq_by(parent.groups, &Enum.sort(&1.children))

          # TODO: consider removing this conditional, since it seems to be always true
          if length(parent_uniq_groups) == parent.group_size do
            [%{nodes: nodes}] = child.groups
            [%{children: child_children} | _] = nodes
            child_nodes = Enum.map(nodes, fn n -> {n.id, n} end) |> Map.new()

            groups =
              Enum.map(parent.groups, fn group ->
                %{
                  index: group.index,
                  children: child_children,
                  nodes:
                    Enum.map(group.children, fn child_id -> Map.fetch!(child_nodes, child_id) end),
                  length: length(group.children)
                }
              end)

            [parent, %{child | groups: groups, group_size: length(groups)}]
          else
            pair
          end
        else
          pair
        end

      [_solo] = pair ->
        pair
    end)
  end

  defp calculate_layers_positions(layers, opts) do
    view_box_middle = opts.view_box_width / 2

    Enum.map(layers, fn layer ->
      groups = calculate_groups_sizes(layer.groups, opts)

      group_gaps = opts.groups_gap * (length(groups) - 1)

      width =
        group_gaps +
          (groups
           |> Enum.map(& &1.width)
           |> Enum.sum())

      start_x = opts.r + view_box_middle - width / 2
      start_y = layer.index * opts.d * (1 + opts.y_gap) + opts.y_gap * opts.d

      %{
        width: width,
        start_x: start_x,
        start_y: start_y,
        groups: calc_groups_positions(groups, {start_x, start_y}, opts)
      }
    end)
  end

  defp calculate_groups_sizes(groups, opts) do
    Enum.map(groups, fn group ->
      children_size = length(group.children)
      group_size = length(group.nodes)

      length_for_width = max(children_size, group_size)

      width = calc_width(length_for_width, opts)

      group
      |> Map.put(:width, width)
      |> Map.put(:length, group_size)
      |> Map.put(:center_on_children?, children_size > group_size)
    end)
  end

  defp calc_width(nodes_count, opts) do
    nodes_count * opts.d + (nodes_count - 1) * opts.gap
  end

  defp calc_groups_positions(groups, layer_coordinates, opts) do
    {updated_groups, _} =
      Enum.reduce(groups, {[], layer_coordinates}, fn group, {new_groups, {last_start_x, y}} ->
        actual_width = calc_width(group.length, opts)

        centered = last_start_x + group.width / 2 - actual_width / 2

        group =
          group
          |> Map.merge(%{start_x: centered, start_y: y, actual_width: actual_width})
          |> Map.update!(:nodes, fn nodes ->
            nodes
            |> Enum.with_index()
            |> Enum.map(fn {layer_node, idx} ->
              position = centered + idx * (opts.d + opts.gap)
              Map.merge(layer_node, %{x: position, y: y, index: idx})
            end)
          end)

        {[group | new_groups], {last_start_x + group.width + opts.groups_gap, y}}
      end)

    Enum.reverse(updated_groups)
  end

  defp circle(node, _opts) do
    background = background(node.data)
    detail = format_detail(node.data)

    %Circle{
      id: node.id,
      children: node.children,
      x: node.x,
      y: node.y,
      bg: background,
      label: if(is_map(node.data), do: node.data.label, else: node.data),
      detail: detail,
      show_detail?: is_map(node.data)
    }
  end

  # TODO: let this be configurable
  defp background(node_data) when is_binary(node_data) do
    "gray"
  end

  defp background(node_data) do
    # This calculation is defining the Hue portion of the HSL color function.
    # By definition, the value 0 is red and the value 120 is green.
    # See: https://developer.mozilla.org/en-US/docs/Web/CSS/color_value#hsl_colors
    hue = 100 - node_data.detail

    "hsl(#{hue}, 80%, 35%)"
  end

  # TODO: let this be configurable
  defp format_detail(node_data) when is_binary(node_data) do
    "#{node_data}%"
  end

  defp format_detail(node_data) do
    "#{node_data.detail}%"
  end

  defp arrow({px, py}, {x, y}, opts) do
    distance = :math.sqrt(:math.pow(x - px, 2) + :math.pow(y - py, 2))

    ratio1 = opts.r / distance
    {x1, y1} = arrow_endpoint(px, py, x, y, ratio1)

    ratio2 = (distance - opts.r - 9) / distance
    {x2, y2} = arrow_endpoint(px, py, x, y, ratio2)

    %Arrow{x1: x1, y1: y1, x2: x2, y2: y2}
  end

  defp arrow_endpoint(x1, y1, x2, y2, ratio) do
    dx = (x2 - x1) * ratio
    dy = (y2 - y1) * ratio

    {x1 + dx, y1 + dy}
  end
end
