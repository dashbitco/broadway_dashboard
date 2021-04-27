defmodule BroadwayDashboard.PipelineGraph do
  alias BroadwayDashboard.Counters

  defmodule Node do
    defstruct data: nil,
              level: 0,
              index: 0,
              pos: 0.0,
              min: 0.0,
              max: 0.0,
              children: []
  end

  defmodule Layer do
    defstruct data: nil,
              level: 0,
              index: 0,
              pos: 0.0,
              min: 0.0,
              max: 0.0,
              nodes: [],
              children: []
  end

  def build_layers(node, pipeline) do
    :rpc.call(node, __MODULE__, :build_layers_callback, [pipeline])
  end

  @spec build_layers_callback(atom()) :: %Layer{}
  def build_layers_callback(pipeline) do
    topology = Broadway.topology(pipeline)

    calc_span(%Layer{
      nodes: build_nodes(pipeline, topology[:producers], "prod", false),
      children: processors_layer(pipeline, topology)
    })
  end

  defp build_nodes(pipeline, stage_details, label_prefix, show_detail? \\ true) do
    stage_details
    |> Enum.flat_map(fn stage ->
      for i <- 0..(stage.concurrency - 1), do: :"#{stage.name}_#{i}"
    end)
    |> Enum.with_index()
    |> Enum.map(fn {name, idx} ->
      factor = Counters.get_processing_factor(pipeline, name)

      %Node{
        data: %{
          label: "#{label_prefix}_#{idx}",
          detail: factor,
          name: name,
          show_detail?: show_detail?
        }
      }
    end)
  end

  defp processors_layer(pipeline, topology) do
    [
      %Layer{
        nodes: build_nodes(pipeline, topology[:processors], "proc"),
        children: batchers_layer(pipeline, topology)
      }
    ]
  end

  defp batchers_layer(pipeline, topology) do
    batchers = topology[:batchers]

    batchers
    |> Enum.sort_by(fn batcher -> batcher.batcher_name end)
    |> Enum.map(fn batcher ->
      factor = Counters.get_processing_factor(pipeline, batcher.batcher_name)

      "batcher_" <> label = short_label(batcher.batcher_name)

      data_node = %Node{
        data: %{label: label, detail: factor, name: batcher.batcher_name, show_detail?: true}
      }

      %Layer{
        nodes: [data_node],
        children: batch_processors_layer(pipeline, batcher, label)
      }
    end)
  end

  defp batch_processors_layer(pipeline, batcher, label) do
    build_nodes(pipeline, [batcher], label)
  end

  defp short_label(name) do
    name
    |> Atom.to_string()
    |> String.split(".")
    |> List.last()
    |> String.downcase()
  end

  defp calc_span(%type{} = node) when type in [Node, Layer] do
    {{_, min, max}, new_node} = calc_span(node, {-1, 0, 0})

    %{new_node | min: min, max: max}
  end

  defp calc_span(%{children: []} = node, {last_pos, min, max}) do
    new_last_pos = last_pos + 1

    {{new_last_pos, min(min, new_last_pos), max(max, new_last_pos)}, %{node | pos: new_last_pos}}
  end

  defp calc_span(%{children: children} = node, {last_pos, min, max}) do
    level = node.level + 1

    {new_children, _, {new_last_pos, new_min, new_max}} =
      Enum.reduce(children, {[], 0, {last_pos, min, max}}, fn child,
                                                              {cur_children, index,
                                                               {last_pos, min, max}} ->
        {{new_last_pos, new_min, new_max}, new_child} =
          calc_span(%{child | index: index, level: level}, {last_pos, min, max})

        {[new_child | cur_children], index + 1,
         {new_last_pos, min(min, new_min), max(max, new_max)}}
      end)

    first_child_pos = List.last(new_children).pos
    last_child_pos = List.first(new_children).pos

    center_pos = (first_child_pos + last_child_pos) / 2

    {min, max} =
      case node do
        %Layer{} ->
          half_length = length(node.nodes) / 2

          min = center_pos - half_length
          max = center_pos + half_length

          {min(new_min, min), max(new_max, max)}

        %Node{} ->
          {min(new_min, first_child_pos), max(new_max, last_child_pos)}
      end

    {{new_last_pos, min, max}, %{node | children: Enum.reverse(new_children), pos: center_pos}}
  end
end
