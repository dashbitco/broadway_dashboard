defmodule BroadwayDashboard.LiveDashboard.PipelineGraphComponent do
  use Phoenix.LiveDashboard.Web, :live_component

  @moduledoc """
  A component for drawing layered graphs.

  This is useful to represent pipelines like we have on
  [BroadwayDashboard](https://hexdocs.pm/broadway_dashboard) where
  each layer points to all nodes of the layer below.
  It draws the layers from top to bottom.

  See: https://en.wikipedia.org/wiki/Layered_graph_drawing

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

      iex> alias BroadwayDashboard.LiveDashboard.PipelineGraphComponent
      iex> alias BroadwayDashboard.LiveDashboard.PipelineGraphComponent.{Layer, Node}
      iex> layers = %Layer{
      ...>   children: [
      ...>     %Layer{
      ...>       level: 1,
      ...>       nodes: [
      ...>         %Node{
      ...>           data: %{
      ...>             detail: 0,
      ...>             label: "proc_0",
      ...>             show_detail?: true
      ...>           },
      ...>           level: 0
      ...>         },
      ...>         %Node{
      ...>           children: [],
      ...>           data: %{
      ...>             detail: 0,
      ...>             label: "proc_1",
      ...>             show_detail?: true
      ...>           },
      ...>           level: 0
      ...>         }
      ...>       ]
      ...>     }
      ...>   ],
      ...>   level: 0,
      ...>   max: 0.5,
      ...>   min: -0.5,
      ...>   nodes: [
      ...>     %Node{
      ...>       children: [],
      ...>       data: %{
      ...>         detail: 0,
      ...>         label: "prod_0",
      ...>         show_detail?: false
      ...>       },
      ...>       level: 0
      ...>     }
      ...>   ]
      ...> }
      iex> pipeline_graph(layers: layers, title: "Pipeline", hint: "A pipeline", opts: [r: 32])
  """

  @default_width 1200
  @default_height 610

  # TODO: move this module to PhoenixLiveDashboard project

  defmodule Layer do
    defstruct level: 0,
              pos: 0.0,
              min: 0.0,
              max: 0.0,
              nodes: [],
              children: []
  end

  defmodule Node do
    defstruct data: %{},
              level: 0,
              pos: 0.0,
              min: 0.0,
              max: 0.0,
              children: []
  end

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
    box_width = opts[:width] || @default_width
    base_width = (layers.max - layers.min) * (d + x_gap)

    margin_left =
      Enum.max([box_width, base_width]) / 2 - base_width / 2 + abs(layers.min) * (d + x_gap) - r

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

  defp build(%Layer{} = layer, opts) do
    arrows_and_circles =
      layer.nodes
      |> Enum.with_index()
      |> Enum.flat_map(fn {node, node_index} ->
        {x, y} = coordinate(layer, node_index, opts)

        children_arrows =
          Enum.flat_map(layer.children, fn child ->
            arrows(x, y, child, opts)
          end)

        [circle(x, y, node, opts) | children_arrows]
      end)

    arrows_and_circles ++ Enum.flat_map(layer.children, fn child -> build(child, opts) end)
  end

  defp build(%Node{children: []} = node, opts) do
    {x, y} = coordinate(node, opts)

    [circle(x, y, node, opts)]
  end

  defp coordinate(node_or_layer, opts) do
    x = (opts.d + opts.x_gap) * node_or_layer.pos + opts.r + opts.margin_left
    y = (opts.d + opts.y_gap) * node_or_layer.level + opts.r + opts.margin_top

    {x, y}
  end

  defp coordinate(%Layer{nodes: [_]} = layer, 0 = _node_index, opts) do
    coordinate(layer, opts)
  end

  defp coordinate(%Layer{} = layer, node_index, opts) do
    n_nodes = length(layer.nodes)

    layer_x = (opts.d + opts.x_gap) * layer.pos + opts.r + opts.margin_left
    layer_width = (n_nodes - 1) * (opts.d + opts.x_gap)
    layer_start_x = layer_x - layer_width / 2

    x = layer_start_x + node_index * layer_width / (n_nodes - 1)
    y = (opts.d + opts.y_gap) * layer.level + opts.r + opts.margin_top

    {x, y}
  end

  defp circle(x, y, node, _opts) do
    background = background(node.data)
    detail = format_detail(node.data)

    %Circle{
      x: x,
      y: y,
      bg: background,
      label: node.data.label,
      detail: detail,
      show_detail?: node.data.show_detail?
    }
  end

  defp background(node_data) do
    # This calculation is defining the Hue portion of the HSL color function.
    # By definition, the value 0 is red and the value 120 is green.
    # See: https://developer.mozilla.org/en-US/docs/Web/CSS/color_value#hsl_colors
    if node_data.show_detail? do
      hue = 100 - node_data.detail

      "hsl(#{hue}, 80%, 35%)"
    else
      "gray"
    end
  end

  defp format_detail(node_data) do
    "#{node_data.detail}%"
  end

  defp arrows(x, y, %Node{} = node, opts) do
    [arrow({x, y}, node, opts)]
  end

  defp arrows(parent_x, parent_y, %Layer{nodes: [_]} = layer, opts) do
    x = (opts.d + opts.x_gap) * layer.pos + opts.r + opts.margin_left
    y = (opts.d + opts.y_gap) * layer.level + opts.r + opts.margin_top

    [arrow({parent_x, parent_y}, {x, y}, opts)]
  end

  defp arrows(parent_x, parent_y, %Layer{} = layer, opts) do
    n_nodes = length(layer.nodes)

    for node_index <- 0..(n_nodes - 1) do
      layer_x = (opts.d + opts.x_gap) * layer.pos + opts.r + opts.margin_left
      layer_width = (n_nodes - 1) * (opts.d + opts.x_gap)
      layer_start_x = layer_x - layer_width / 2

      x = layer_start_x + node_index * layer_width / (n_nodes - 1)
      y = (opts.d + opts.y_gap) * layer.level + opts.r + opts.margin_top

      arrow({parent_x, parent_y}, {x, y}, opts)
    end
  end

  defp arrow({px, py}, {x, y}, opts) do
    distance = :math.sqrt(:math.pow(x - px, 2) + :math.pow(y - py, 2))

    ratio1 = opts.r / distance
    {x1, y1} = arrow_endpoint(px, py, x, y, ratio1)

    ratio2 = (distance - opts.r - 9) / distance
    {x2, y2} = arrow_endpoint(px, py, x, y, ratio2)

    %Arrow{x1: x1, y1: y1, x2: x2, y2: y2}
  end

  defp arrow({px, py}, node, opts) do
    x = (opts.d + opts.x_gap) * node.pos + opts.r + opts.margin_left
    y = (opts.d + opts.y_gap) * node.level + opts.r + opts.margin_top

    arrow({px, py}, {x, y}, opts)
  end

  defp arrow_endpoint(x1, y1, x2, y2, ratio) do
    dx = (x2 - x1) * ratio
    dy = (y2 - y1) * ratio

    {x1 + dx, y1 + dy}
  end

  defp graph_dimensions(circles, opts) do
    max_height = Enum.max([@default_height | Enum.map(circles, fn circle -> circle.y end)])
    max_width = Enum.max([@default_width | Enum.map(circles, fn circle -> circle.x end)])

    {max_width + opts.x_gap, max_height}
  end
end
