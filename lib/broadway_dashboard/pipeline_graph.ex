defmodule BroadwayDashboard.PipelineGraph do
  alias BroadwayDashboard.Counters
  alias BroadwayDashboard.LiveDashboard.LayeGraphComponent

  # TODO: maybe move type definitions to Broadway.topology/1
  @type topology_desc :: %{
          :name => atom(),
          :concurrency => pos_integer(),
          optional(:batcher_name) => atom()
        }
  @type topology_item :: {:producers | :processors | :batchers, topology_desc()}

  @spec build_layers(atom(), [topology_item()]) :: [LayeGraphComponent.layer()]
  def build_layers(pipeline, topology) when is_atom(pipeline) and is_list(topology) do
    # The order of steps is important here.
    steps =
      if with_batchers?(topology) do
        [:batch_processors, :batchers, :processors, :producers]
      else
        [:processors, :producers]
      end

    build_layers(pipeline, topology, steps)
  end

  defp with_batchers?(topology) do
    topology[:batchers] != []
  end

  defp build_layers(pipeline, topology, steps) do
    build_layers(pipeline, topology, steps, [])
  end

  defp build_layers(_pipeline, _topology, [], result), do: result

  defp build_layers(pipeline, topology, [step | steps], result) do
    previous_layer = List.first(result) || []

    layer =
      case step do
        :producers ->
          build_nodes(pipeline, topology[:producers], "prod", previous_layer, show_factor?: false)

        :processors ->
          build_nodes(pipeline, topology[:processors], "proc", previous_layer)

        :batchers ->
          topology[:batchers]
          |> Enum.sort_by(fn batcher -> batcher.batcher_name end)
          |> Enum.map(fn batcher ->
            {:ok, factor} = Counters.fetch_processing_factor(pipeline, batcher.batcher_name)

            "batcher_" <> label = short_label(batcher.batcher_name)

            children_ids =
              previous_layer
              |> Enum.filter(fn batch_proc ->
                String.starts_with?(Atom.to_string(batch_proc.id), Atom.to_string(batcher.name))
              end)
              |> Enum.map(& &1.id)

            %{
              id: batcher.batcher_name,
              data: %{label: label, detail: factor},
              children: children_ids
            }
          end)

        :batch_processors ->
          build_nodes(pipeline, topology[:batchers], "proc", previous_layer)
      end

    build_layers(pipeline, topology, steps, [layer | result])
  end

  defp build_nodes(pipeline, stage_details, label_prefix, children_layer, opts \\ []) do
    stage_details
    |> Enum.map(fn stage ->
      for i <- 0..(stage.concurrency - 1), do: :"#{stage.name}_#{i}"
    end)
    |> Enum.flat_map(fn stage_group ->
      stage_group
      |> Enum.with_index()
      |> Enum.map(fn {name, idx} ->
        show_factor? = Keyword.get(opts, :show_factor?, true)

        data =
          if show_factor? do
            {:ok, factor} = Counters.fetch_processing_factor(pipeline, name)

            %{
              label: "#{label_prefix}_#{idx}",
              detail: factor
            }
          else
            "#{label_prefix}_#{idx}"
          end

        %{
          id: name,
          children: Enum.map(children_layer, & &1.id),
          data: data
        }
      end)
    end)
  end

  defp short_label(name) do
    name
    |> Atom.to_string()
    |> String.split(".")
    |> List.last()
    |> String.downcase()
  end
end
