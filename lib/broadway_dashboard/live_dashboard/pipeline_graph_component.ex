defmodule BroadwayDashboard.LiveDashboard.PipelineGraphComponent do
  use Phoenix.LiveDashboard.Web, :live_component

  @moduledoc """
  A component for drawing layered graphs.

  This is useful to represent pipelines like we have on
  [BroadwayDashboard](https://hexdocs.pm/broadway_dashboard) where
  each layer points to all nodes of the layer below.
  It draws the layers from top to bottom.

  See: https://en.wikipedia.org/wiki/Layered_graph_drawing

  The calculation of layers and node positions is done automatically
  based on options. But the expected structure is a layer with multiple
  nodes and children layers. The bottom layers can have node children.

  ## Options

    * `:layers` - a graph of layers with nodes. They represent
      our graph structure (see example).
    * `:opts` - drawing options
      * `:r` - the ratio of our circles.
      * `:width` - the width in pixels of our drawing area (optional).
        A scroll is added if graph is bigger than our drawing area.
      * `:margin_top` - the top margin in pixels.
      * `:margin_left` - the left margin in pixels.
      * `:x_gap` - the horizontal gap between circles.
      * `:y_gap` - the vertical gap between circles.
      * `:y_label_offset` - the vertical offset for the circle label.
      * `:y_detail_offset` - the vertical offset for the circle detail.

  ## Examples

      iex> layers = [
      ...>   [
      ...>     %{
      ...>       id: MyPipeline.Broadway.Producer_0,
      ...>       data: %{
      ...>         detail: 0,
      ...>         label: "prod_0",
      ...>         show_detail?: false
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
      iex> pipeline_graph(layers: layers, title: "Pipeline", hint: "A pipeline", opts: [r: 32])
  """

  @default_width 1200
  @default_height 610

  # TODO: move this module to PhoenixLiveDashboard project

  defmodule Arrow do
    defstruct [:x1, :y1, :x2, :y2]
  end

  defmodule Circle do
    defstruct [:x, :y, :label, :detail, :show_detail?, :bg]
  end

  @impl true
  def mount(socket) do
    {:ok, socket}
  end

  @impl true
  def render(assigns) do
    layers = assigns.layers
    opts = Map.get(assigns, :opts, [])

    r = opts[:r] || 42

    d = r + r
    x_gap = opts[:x_gap] || 20
    # box_width = opts[:width] || @default_width
    # base_width = (layers.max - layers.min) * (d + x_gap)

    # margin_left =
    # Enum.max([box_width, base_width]) / 2 - base_width / 2 + abs(layers.min) * (d + x_gap) - r
    margin_left = 20

    opts = %{
      r: r,
      d: d,
      margin_top: opts[:margin_top] || 20,
      margin_left: margin_left,
      x_gap: x_gap,
      y_gap: opts[:y_gap] || 82,
      y_label_offset: opts[:y_label_offset] || 5,
      y_detail_offset: opts[:y_detail_offset] || 18
    }

    {circles, arrows} =
      layers
      |> build(opts)
      |> Enum.split_with(fn el -> match?(%Circle{}, el) end)

    {width, height} = graph_dimensions(circles, opts)

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
      <div class="card-body card-graph broadway-dashboard" style="overflow-x: auto; min-height: 680px">
        <svg style="height: <%= height %>px; width: <%= width %>px;">
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

            .graph-circle-label {
              font-size: 1rem;
            }

            .graph-circle-detail {
              font-size: 0.9rem;
            }
          </style>
          <defs>
            <marker id="arrow" markerWidth="10" markerHeight="10" refX="0" refY="3" orient="auto" markerUnits="strokeWidth">
              <path d="M0,0 L0,6 L9,3 z" class="graph-line" />
            </marker>
          </defs>
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
    layers
    |> Enum.with_index()
    |> Enum.flat_map(fn {layer, index} ->
      layer
      |> Enum.with_index()
      |> Enum.map(fn {layer_node, node_index} ->
        {x, y} = coordinate({layer, index}, {layer_node, node_index}, opts)

        circle(x, y, layer_node, opts)
      end)
    end)
  end

  # defp build(%Layer{} = layer, opts) do
  #   arrows_and_circles =
  #     layer.nodes
  #     |> Enum.with_index()
  #     |> Enum.flat_map(fn {node, node_index} ->
  #       {x, y} = coordinate(layer, node_index, opts)
  #
  #       children_arrows =
  #         Enum.flat_map(layer.children, fn child ->
  #           arrows(x, y, child, opts)
  #         end)
  #
  #       [circle(x, y, node, opts) | children_arrows]
  #     end)
  #
  #   arrows_and_circles ++ Enum.flat_map(layer.children, fn child -> build(child, opts) end)
  # end

  # defp build(%Node{children: []} = node, opts) do
  #   {x, y} = coordinate(node, opts)
  #
  #   [circle(x, y, node, opts)]
  # end

  # defp coordinate(node_or_layer, opts) do
  #   x = (opts.d + opts.x_gap) * node_or_layer.pos + opts.r + opts.margin_left
  #   y = (opts.d + opts.y_gap) * node_or_layer.level + opts.r + opts.margin_top
  #
  #   {x, y}
  # end

  # defp coordinate(%Layer{nodes: [_]} = layer, 0 = _node_index, opts) do
  #   coordinate(layer, opts)
  # end

  defp coordinate({layer, index}, {_layer_node, node_index}, opts) do
    n_nodes = length(layer)

    # TODO: check how we can swap `layer.pos` (the index)
    layer_x = (opts.d + opts.x_gap) * index + opts.r + opts.margin_left
    layer_width = n_nodes * (opts.d + opts.x_gap)
    layer_start_x = layer_x - layer_width / 2

    x = layer_start_x + node_index * layer_width / n_nodes
    y = (opts.d + opts.y_gap) * index + opts.r + opts.margin_top

    {x, y}
  end

  defp circle(x, y, node, _opts) do
    background = background(node.data)
    detail = format_detail(node.data)

    %Circle{
      x: x,
      y: y,
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

  defp graph_dimensions(circles, opts) do
    max_height = Enum.max([@default_height | Enum.map(circles, fn circle -> circle.y end)])
    max_width = Enum.max([@default_width | Enum.map(circles, fn circle -> circle.x end)])

    {max_width + opts.x_gap, max_height}
  end

  # TODO: adapt arrows
  # defp arrows(x, y, %Node{} = node, opts) do
  #   [arrow({x, y}, node, opts)]
  # end

  # defp arrows(parent_x, parent_y, %Layer{nodes: [_]} = layer, opts) do
  #   x = (opts.d + opts.x_gap) * layer.pos + opts.r + opts.margin_left
  #   y = (opts.d + opts.y_gap) * layer.level + opts.r + opts.margin_top

  #   [arrow({parent_x, parent_y}, {x, y}, opts)]
  # end

  # defp arrows(parent_x, parent_y, %Layer{} = layer, opts) do
  #   n_nodes = length(layer.nodes)

  #   for node_index <- 0..(n_nodes - 1) do
  #     layer_x = (opts.d + opts.x_gap) * layer.pos + opts.r + opts.margin_left
  #     layer_width = (n_nodes - 1) * (opts.d + opts.x_gap)
  #     layer_start_x = layer_x - layer_width / 2

  #     x = layer_start_x + node_index * layer_width / (n_nodes - 1)
  #     y = (opts.d + opts.y_gap) * layer.level + opts.r + opts.margin_top

  #     arrow({parent_x, parent_y}, {x, y}, opts)
  #   end
  # end

  # defp arrow({px, py}, {x, y}, opts) do
  #   distance = :math.sqrt(:math.pow(x - px, 2) + :math.pow(y - py, 2))

  #   ratio1 = opts.r / distance
  #   {x1, y1} = arrow_endpoint(px, py, x, y, ratio1)

  #   ratio2 = (distance - opts.r - 9) / distance
  #   {x2, y2} = arrow_endpoint(px, py, x, y, ratio2)

  #   %Arrow{x1: x1, y1: y1, x2: x2, y2: y2}
  # end

  # defp arrow({px, py}, node, opts) do
  #   x = (opts.d + opts.x_gap) * node.pos + opts.r + opts.margin_left
  #   y = (opts.d + opts.y_gap) * node.level + opts.r + opts.margin_top

  #   arrow({px, py}, {x, y}, opts)
  # end

  # defp arrow_endpoint(x1, y1, x2, y2, ratio) do
  #   dx = (x2 - x1) * ratio
  #   dy = (y2 - y1) * ratio

  #   {x1 + dx, y1 + dy}
  # end

  # def calc_span(%type{} = node) when type in [Node, Layer] do
  #   {{_, min, max}, new_node} = calc_span(node, {-1, 0, 0})

  #   %{new_node | min: min, max: max}
  # end

  # defp calc_span(%{children: []} = node, {last_pos, min, max}) do
  #   new_last_pos = last_pos + 1

  #   {{new_last_pos, min(min, new_last_pos), max(max, new_last_pos)}, %{node | pos: new_last_pos}}
  # end

  # defp calc_span(%{children: children} = node, {last_pos, min, max}) do
  #   level = node.level + 1

  #   {new_children, {new_last_pos, new_min, new_max}} =
  #     Enum.reduce(children, {[], {last_pos, min, max}}, fn child,
  #                                                          {cur_children, {last_pos, min, max}} ->
  #       {{new_last_pos, new_min, new_max}, new_child} =
  #         calc_span(%{child | level: level}, {last_pos, min, max})

  #       {[new_child | cur_children], {new_last_pos, min(min, new_min), max(max, new_max)}}
  #     end)

  #   [%{pos: first_child_pos} | _] = Enum.reverse(new_children)
  #   [%{pos: last_child_pos} | _] = new_children

  #   center_pos = (first_child_pos + last_child_pos) / 2

  #   {min, max} =
  #     case node do
  #       %Layer{} ->
  #         half_length = length(node.nodes) / 2

  #         min = center_pos - half_length
  #         max = center_pos + half_length

  #         {min(new_min, min), max(new_max, max)}

  #       %Node{} ->
  #         {min(new_min, first_child_pos), max(new_max, last_child_pos)}
  #     end

  #   {{new_last_pos, min, max}, %{node | children: Enum.reverse(new_children), pos: center_pos}}
  # end
end
