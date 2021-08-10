defmodule BroadwayDashboard.Telemetry do
  @moduledoc false

  # Measurements of pipelines are based on telemetry events.
  #
  # The load of a stage is calculated based on the time
  # it took from the last execution to the current one.
  # If this time is shorter, it means that the stage is
  # doing more work.

  alias BroadwayDashboard.Counters

  def attach(parent, pipeline, counters) do
    events = [
      [:broadway, :topology, :init],
      [:broadway, :processor, :start],
      [:broadway, :processor, :stop],
      [:broadway, :processor, :message, :exception],
      [:broadway, :batcher, :start],
      [:broadway, :batcher, :stop],
      [:broadway, :batch_processor, :start],
      [:broadway, :batch_processor, :stop]
    ]

    :telemetry.attach_many({__MODULE__, parent}, events, &handle_event/4, {pipeline, counters})
  end

  def detach(parent) do
    :telemetry.detach({__MODULE__, parent})
  end

  def handle_event([:broadway, :topology, :init], _, metadata, {pipeline, _}) do
    if metadata.config[:name] == pipeline do
      BroadwayDashboard.Metrics.ensure_counters_restarted(pipeline)
    end
  end

  def handle_event(
        [:broadway, stage_layer, :start],
        measurements,
        %{topology_name: pipeline} = metadata,
        {pipeline, counters}
      )
      when stage_layer in [:processor, :batcher, :batch_processor] do
    case stage_layer do
      :processor ->
        :ok = Counters.put_processor_start(counters, metadata.index, measurements.system_time)

      :batcher ->
        :ok = Counters.put_batcher_start(counters, metadata.batcher_key, measurements.system_time)

      :batch_processor ->
        :ok =
          Counters.put_batch_processor_start(
            counters,
            metadata.batch_info.batcher,
            metadata.index,
            measurements.system_time
          )
    end
  end

  def handle_event(
        [:broadway, stage_layer, :stop],
        measurements,
        %{topology_name: pipeline} = metadata,
        {pipeline, counters}
      )
      when stage_layer in [:processor, :batcher, :batch_processor] do
    case stage_layer do
      :processor ->
        {:ok, start_time} = Counters.fetch_processor_start(counters, metadata.index)
        {:ok, last_end_time} = Counters.fetch_processor_end(counters, metadata.index)

        workload = calc_workload(start_time, last_end_time, measurements.duration)

        end_system_time = start_time + measurements.duration

        :ok = Counters.put_processor_end(counters, metadata.index, end_system_time)
        :ok = Counters.put_processor_workload(counters, metadata.index, workload)

        # Here we measure only because it can occur a failure or
        # we don't have batchers and we "Ack" in the processor.
        :ok =
          Counters.incr(
            counters,
            length(metadata.successful_messages_to_ack),
            length(metadata.failed_messages)
          )

      :batcher ->
        {:ok, start_time} = Counters.fetch_batcher_start(counters, metadata.batcher_key)
        {:ok, last_end_time} = Counters.fetch_batcher_end(counters, metadata.batcher_key)

        workload = calc_workload(start_time, last_end_time, measurements.duration)

        end_system_time = start_time + measurements.duration

        :ok = Counters.put_batcher_end(counters, metadata.batcher_key, end_system_time)
        :ok = Counters.put_batcher_workload(counters, metadata.batcher_key, workload)

      :batch_processor ->
        key = metadata.batch_info.batcher
        index = metadata.index

        {:ok, start_time} = Counters.fetch_batch_processor_start(counters, key, index)
        {:ok, last_end_time} = Counters.fetch_batch_processor_end(counters, key, index)

        workload = calc_workload(start_time, last_end_time, measurements.duration)

        end_system_time = start_time + measurements.duration

        :ok = Counters.put_batch_processor_end(counters, key, index, end_system_time)
        :ok = Counters.put_batch_processor_workload(counters, key, index, workload)

        :ok =
          Counters.incr(
            counters,
            length(metadata.successful_messages),
            length(metadata.failed_messages)
          )
    end
  end

  def handle_event(
        [:broadway, :processor, :message, :exception],
        _measurements,
        %{topology_name: pipeline} = _metadata,
        {pipeline, counters}
      ) do
    :ok = Counters.incr(counters, 0, 1)
  end

  # Ignore events from other pipelines
  def handle_event(_, _, _, _), do: :ok

  defp calc_workload(start_time, last_end_time, duration) do
    idle_time = start_time - last_end_time
    round(duration / (idle_time + duration) * 100)
  end
end
