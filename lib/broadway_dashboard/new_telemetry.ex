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
      [:broadway, :consumer, :start],
      [:broadway, :consumer, :stop]
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
      when stage_layer in [:processor, :batcher, :consumer] do
    case stage_layer do
      :processor ->
        :ok = Counters.put_processor_start(counters, metadata.index, measurements.time)

      :batcher ->
        :ok = Counters.put_batcher_start(counters, metadata.batcher_key, measurements.time)

      :consumer ->
        :ok =
          Counters.put_batch_processor_start(
            counters,
            metadata.batch_info.batcher,
            metadata.index,
            measurements.time
          )
    end
  end

  def handle_event(
        [:broadway, stage_layer, :stop],
        measurements,
        %{topology_name: pipeline} = metadata,
        {pipeline, counters}
      )
      when stage_layer in [:processor, :batcher, :consumer] do
    case stage_layer do
      :processor ->
        {:ok, start_time} = Counters.get_processor_start(counters, metadata.index)
        {:ok, last_end_time} = Counters.get_processor_end(counters, metadata.index)

        factor = calc_factor(start_time, last_end_time, measurements.duration)

        :ok = Counters.put_processor_end(counters, metadata.index, measurements.time)
        :ok = Counters.put_processor_processing_factor(counters, metadata.index, factor)

        # Here we measure only because it can occur a failure or
        # we don't have batchers and we "Ack" in the processor.
        :ok =
          Counters.incr(
            counters,
            length(metadata.successful_messages_to_ack),
            length(metadata.failed_messages)
          )

      :batcher ->
        {:ok, start_time} = Counters.get_batcher_start(counters, metadata.batcher_key)
        {:ok, last_end_time} = Counters.get_batcher_end(counters, metadata.batcher_key)

        factor = calc_factor(start_time, last_end_time, measurements.duration)

        :ok = Counters.put_batcher_end(counters, metadata.batcher_key, measurements.time)
        :ok = Counters.put_batcher_processing_factor(counters, metadata.batcher_key, factor)

      :consumer ->
        key = metadata.batch_info.batcher
        index = metadata.index

        {:ok, start_time} = Counters.get_batch_processor_start(counters, key, index)
        {:ok, last_end_time} = Counters.get_batch_processor_end(counters, key, index)

        factor = calc_factor(start_time, last_end_time, measurements.duration)

        :ok = Counters.put_batch_processor_end(counters, key, index, measurements.time)
        :ok = Counters.put_batch_processor_processing_factor(counters, key, index, factor)

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

  defp calc_factor(start_time, last_end_time, duration) do
    idle_time = start_time - last_end_time
    round(duration / (idle_time + duration) * 100)
  end
end
