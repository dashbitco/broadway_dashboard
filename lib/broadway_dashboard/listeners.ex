defmodule BroadwayDashboard.Listeners do
  @moduledoc false

  # It has the basic operations for adding and remove
  # listeners for a given pipeline.

  def add(listeners, pipeline, listener_pid) do
    pipeline_listeners =
      listeners
      |> Map.get(pipeline, MapSet.new())
      |> MapSet.put(listener_pid)

    Map.put(listeners, pipeline, pipeline_listeners)
  end

  def remove(listeners, listener_pid) do
    listeners
    |> Enum.map(fn {pipeline, pids_set} ->
      pids_set =
        if MapSet.member?(pids_set, listener_pid) do
          MapSet.delete(pids_set, listener_pid)
        else
          pids_set
        end

      {pipeline, pids_set}
    end)
    |> Map.new()
  end
end
