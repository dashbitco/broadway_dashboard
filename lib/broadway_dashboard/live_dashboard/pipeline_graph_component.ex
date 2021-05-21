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

  @max_node_width 75

  # TODO: move this module to PhoenixLiveDashboard project

  defmodule Arrow do
    defstruct [:x1, :y1, :x2, :y2]
  end

  defmodule Circle do
    defstruct [:id, :x, :y, :label, :detail, :show_detail?, :bg, :children]
  end

  @impl true
  def mount(socket) do
    {:ok, socket}
  end

  @impl true
  def render(assigns) do
    layers = assigns.layers
    opts = Map.get(assigns, :opts, [])

    # Note that margin top, X and Y gaps are relative to the size of a circle.
    # The circle size is calculated.
    opts = %{
      view_box_width: 1000,
      view_box_height: 1000,
      margin_top: 0.5,
      x_gap: 0.2,
      y_gap: 1.0,
      y_label_offset: opts[:y_label_offset] || 5,
      y_detail_offset: opts[:y_detail_offset] || 18
    }

    {circles, arrows, rects, opts} = build(layers, opts)

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
        <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 <%= opts.view_box_width%> <%= opts.view_box_height %>">
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


          <%= for arrow <- arrows do %>
            <line x1="<%= arrow.x1 %>" y1="<%= arrow.y1 %>" x2="<%= arrow.x2 %>" y2="<%= arrow.y2 %>" class="graph-line" marker-end="url(#arrow)"/>
          <% end %>
          <%= for rect <- rects do %>
            <rect x="<%= rect.x %>" y="<%= rect.y %>" width="<%= rect.width %>" height="<%= opts.d %>" fill="#ccc" stroke="pink" />
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

    node_width = opts.view_box_width / (max_nodes + (max_nodes - 1) * opts.x_gap)

    node_width =
      if node_width > @max_node_width do
        @max_node_width
      else
        node_width
      end

    radius = node_width / 2

    gap = node_width * opts.x_gap

    opts =
      opts
      |> Map.put_new(:d, node_width)
      |> Map.put_new(:r, radius)
      |> Map.put_new(:gap, gap)

    view_box_middle = opts.view_box_width / 2

    layers =
      layers
      |> Enum.with_index()
      |> Enum.map(fn {layer, index} ->
        groups =
          layer
          |> Enum.chunk_by(&Enum.sort(&1.children))
          |> Enum.with_index()
          |> Enum.map(fn {group, group_index} ->
            group_size = length(group)

            [member | _] = group
            children_size = length(member.children)

            length_for_width =
              if children_size > group_size do
                children_size
              else
                group_size
              end

            width = calc_width(length_for_width, opts)

            %{
              index: group_index,
              length: group_size,
              width: width,
              nodes: group,
              children: member.children,
              center_on_children?: children_size > group_size
            }
          end)

        len = length(layer)
        # TODO: add more gap in case group children are not shared
        group_gaps = opts.gap * (length(groups) - 1)

        width =
          group_gaps +
            (groups
             |> Enum.map(& &1.width)
             |> Enum.sum())

        start_x = opts.r + view_box_middle - width / 2
        start_y = index * opts.d * (1 + opts.y_gap) + opts.y_gap * opts.d

        %{
          length: len,
          width: width,
          start_x: start_x,
          start_y: start_y,
          index: index,
          groups: calc_groups_positions(groups, {start_x, start_y}, opts)
        }
      end)

    circles =
      layers
      |> Enum.flat_map(fn layer ->
        Enum.flat_map(layer.groups, fn group ->
          Enum.map(group.nodes, fn child_node ->
            circle(child_node, opts)
          end)
        end)
      end)

    circles_map = circles |> Enum.map(fn circle -> {circle.id, circle} end) |> Map.new()

    arrows =
      Enum.flat_map(circles, fn circle ->
        Enum.map(circle.children, fn child_id ->
          child = Map.fetch!(circles_map, child_id)
          arrow({circle.x, circle.y}, {child.x, child.y}, opts)
        end)
      end)

    #  TODO: remove me
    # rects =
    #   Enum.flat_map(layers, fn layer ->
    #     Enum.map(layer.groups, fn group -> rect(group, opts) end)
    #   end)

    # rects =
    #   Enum.map(layers, fn layer ->
    #     rect(layer, opts)
    #   end)
    max_layer_y = Enum.map(layers, & &1.start_y) |> Enum.max()

    bottom_end = max_layer_y + opts.d * (opts.y_gap + 0.2)

    opts =
      if bottom_end < opts.view_box_height do
        Map.put(opts, :view_box_height, bottom_end)
      else
        opts
      end

    # TODO: remove rects
    {circles, arrows, [], opts}
  end

  defp calc_width(nodes_count, opts) do
    nodes_count * opts.d + (nodes_count - 1) * opts.gap
  end

  defp calc_groups_positions(groups, layer_coordinates, opts) do
    {updated_groups, _} =
      Enum.reduce(groups, {[], layer_coordinates}, fn group, {new_groups, {last_start_x, y}} ->
        actual_width = calc_width(group.length, opts)

        # TODO: check if "d" is actually "r"
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

        {[group | new_groups], {last_start_x + group.width + opts.gap, y}}
      end)

    Enum.reverse(updated_groups)
  end

  # defp rect(group, opts) do
  #   y = group.start_y - opts.r
  #
  #   y =
  #     if rem(group.index, 2) == 0 do
  #       y
  #     else
  #       y - opts.r / 2
  #     end
  #
  #   %{x: group.start_x - opts.r, y: y, width: group.width}
  # end

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
