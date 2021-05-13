defmodule BroadwayDashboard.PipelineGraph do
  alias BroadwayDashboard.Counters

  alias BroadwayDashboard.LiveDashboard.PipelineComponent.{Layer, Node}

  # TODO: maybe move type definitions to Broadway.topology/1
  @type topology_desc :: %{
          :name => atom(),
          :concurrency => pos_integer(),
          optional(:batcher_name) => atom()
        }
  @type topology_item :: {:producers | :processors | :batchers, topology_desc()}

  @spec build_layers(atom(), [topology_item()]) :: %Layer{}
  def build_layers(pipeline, topology) when is_atom(pipeline) and is_list(topology) do
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
      {:ok, factor} = Counters.fetch_processing_factor(pipeline, name)

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
      {:ok, factor} = Counters.fetch_processing_factor(pipeline, batcher.batcher_name)

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

    {new_children, {new_last_pos, new_min, new_max}} =
      Enum.reduce(children, {[], {last_pos, min, max}}, fn child,
                                                           {cur_children, {last_pos, min, max}} ->
        {{new_last_pos, new_min, new_max}, new_child} =
          calc_span(%{child | level: level}, {last_pos, min, max})

        {[new_child | cur_children], {new_last_pos, min(min, new_min), max(max, new_max)}}
      end)

    [%{pos: first_child_pos} | _] = Enum.reverse(new_children)
    [%{pos: last_child_pos} | _] = new_children

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
