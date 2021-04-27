defmodule BroadwayDashboard.Telemetry do
  @measurable_start_stages [:processor, :batcher, :consumer]

  alias BroadwayDashboard.Counters

  def attach(parent) do
    events = [
      [:broadway, :topology, :init],
      [:broadway, :processor, :start],
      [:broadway, :processor, :stop],
      [:broadway, :processor, :message, :exception],
      [:broadway, :consumer, :start],
      [:broadway, :consumer, :stop],
      [:broadway, :batcher, :start],
      [:broadway, :batcher, :stop]
    ]

    id = {__MODULE__, parent}

    :telemetry.attach_many(id, events, &handle_event/4, %{})
  end

  def detach(parent) do
    :telemetry.detach({__MODULE__, parent})
  end

  # TODO: check if this is OK/secure to handle restarts
  # Or if this is really necessary.
  def handle_event([:broadway, :topology, :init], _, metadata, _) do
    BroadwayDashboard.Metrics.ensure_counters_restarted(metadata.config[:name])
  end

  # Note that `self()` inside `handle_event/4` is the process that is
  # dispatching the event inside Broadway.
  def handle_event([:broadway, stage, :start], measurements, metadata, _)
      when stage in @measurable_start_stages do
    measure_start(measurements, metadata)
  end

  def handle_event([:broadway, :batcher, :stop], measurements, metadata, _) do
    measure_stop(measurements, metadata)
  end

  def handle_event([:broadway, :processor, :stop], measurements, metadata, _) do
    # Here we measure only because it can occur a failure or
    # we don't have batchers and we "Ack" in the processor.
    Counters.incr(
      pipeline_name(metadata.name),
      length(metadata.successful_messages_to_ack),
      length(metadata.failed_messages)
    )

    measure_stop(measurements, metadata)
  end

  def handle_event([:broadway, :consumer, :stop], measurements, metadata, _) do
    :ok =
      Counters.incr(
        pipeline_name(metadata.name),
        length(metadata.successful_messages),
        length(metadata.failed_messages)
      )

    measure_stop(measurements, metadata)
  end

  # TODO: confirm if exceptions are counted as failed messages in the processors.
  def handle_event([:broadway, :processor, :message, :exception], _measurements, metadata, _) do
    :ok =
      Counters.incr(
        pipeline_name(metadata.name),
        0,
        1
      )

    :ok
  end

  defp measure_start(measurements, metadata) do
    Counters.put_start(pipeline_name(metadata.name), metadata.name, measurements.time)

    :ok
  end

  defp measure_stop(measurements, metadata) do
    pipeline = pipeline_name(metadata.name)
    name = metadata.name

    start_time = Counters.get_start(pipeline, name)
    last_end_time = Counters.get_end(pipeline, name)

    idle_time = start_time - last_end_time
    processing_factor = round(measurements.duration / (idle_time + measurements.duration) * 100)

    Counters.put_end(pipeline, name, measurements.time)
    Counters.put_processing_factor(pipeline, name, processing_factor)

    :ok
  end

  defp pipeline_name(name) do
    name
    |> Atom.to_string()
    |> String.split(".Broadway.")
    |> List.first()
    |> String.to_existing_atom()
  end
end
