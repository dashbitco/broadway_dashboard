defmodule BroadwayDashboard.Teleporter do
  # It copies the base files to a node, in order
  # to track the pipelines.
  @modules [
    BroadwayDashboard.Counters,
    BroadwayDashboard.Metrics,
    BroadwayDashboard.PipelineGraph,
    BroadwayDashboard.Telemetry
  ]

  @spec teleport_metrics_code(Node.t()) :: :ok | {:error, atom()}
  def teleport_metrics_code(node) do
    case :rpc.call(node, :code, :is_loaded, [hd(@modules)]) do
      false ->
        result =
          for module <- @modules do
            {_module, binary, filename} = :code.get_object_code(module)

            :rpc.call(node, :code, :load_binary, [module, filename, binary])
          end

        if Enum.all?(result, &match?({:module, _}, &1)) do
          :ok
        else
          {:error, :not_loaded}
        end

      {:file, _} ->
        :ok

      {:badrpc, _} = error ->
        {:error, error}
    end
  end
end
