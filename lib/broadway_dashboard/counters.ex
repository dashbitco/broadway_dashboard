defmodule BroadwayDashboard.Counters do
  @moduledoc false

  # Keep counters for each pipeline.

  # This is necessary to measure the activity for each stage
  # and the throughput of a Broadway pipeline.
  # We do that by storing the count of successful and failed
  # events, and for each stage we store the following:
  # - start time
  # - end time
  # - processing factor
  # The calculation of processing factor is done at
  # BroadwayDashboard.EventHandler.

  @successful_col 1
  @failed_col 2
  @process_columns 3

  def start(pipeline) do
    if :persistent_term.get({__MODULE__, pipeline}, nil) do
      :already_started
    else
      start!(pipeline)
    end
  end

  def start!(pipeline) do
    topology = Broadway.topology(pipeline)

    processes_atomics =
      Enum.reduce(topology, Map.new(), fn {stage, details}, atomics ->
        case stage do
          :batchers ->
            Enum.reduce(details, atomics, fn batcher, acc ->
              acc
              |> put_atomics(batcher.batcher_name)
              |> put_atomics(batcher.name, batcher.concurrency)
            end)

          _ ->
            Enum.reduce(details, atomics, fn stage_detail, acc ->
              put_atomics(acc, stage_detail.name, stage_detail.concurrency)
            end)
        end
      end)

    # The counters are used for overall counting.
    # Successful and error (2).
    :persistent_term.put(
      {__MODULE__, pipeline},
      {:counters.new(2, [:write_concurrency]), processes_atomics}
    )

    :ok
  end

  defp put_atomics(map, name) do
    # It's required to be signed because `System.monotonic_time()` can
    # be negative.
    Map.put_new(map, name, :atomics.new(@process_columns, signed: true))
  end

  defp put_atomics(map, name, concurrency) do
    Enum.reduce(0..concurrency, map, fn idx, acc ->
      put_atomics(acc, :"#{name}_#{idx}")
    end)
  end

  def put_start(pipeline, name, start) do
    put_at(1, pipeline, name, start)
  end

  def put_end(pipeline, name, end_time) do
    put_at(2, pipeline, name, end_time)
  end

  def put_processing_factor(pipeline, name, factor) do
    put_at(3, pipeline, name, factor)
  end

  defp put_at(index, pipeline, name, value) do
    atomics = get_processes_atomics(pipeline)

    # TODO: maybe implement fallback to store if doesn't exist
    process_atomic = Map.fetch!(atomics, name)
    :atomics.put(process_atomic, index, value)
  end

  def get_start(pipeline, name) do
    get_at(1, pipeline, name)
  end

  def get_end(pipeline, name) do
    get_at(2, pipeline, name)
  end

  def get_processing_factor(pipeline, name) do
    get_at(3, pipeline, name)
  end

  defp get_at(index, pipeline, name) do
    atomics = get_processes_atomics(pipeline)

    # TODO: maybe implement fallback to store if doesn't exist
    process_atomic = Map.fetch!(atomics, name)
    :atomics.get(process_atomic, index)
  end

  defp get_processes_atomics(pipeline) do
    {_, atomics} = :persistent_term.get({__MODULE__, pipeline})

    atomics
  end

  def incr(pipeline, successes, fails) do
    counters_ref = get_counters(pipeline)

    :counters.add(counters_ref, @successful_col, successes)
    :counters.add(counters_ref, @failed_col, fails)

    :ok
  end

  def count(node, pipeline) do
    :rpc.call(node, __MODULE__, :count_callback, [pipeline])
  end

  def count_callback(pipeline) do
    counters_ref = get_counters(pipeline)

    successful = :counters.get(counters_ref, @successful_col)
    failed = :counters.get(counters_ref, @failed_col)

    {successful, failed}
  end

  defp get_counters(pipeline) do
    {counters_ref, _} = :persistent_term.get({__MODULE__, pipeline})

    counters_ref
  end
end
