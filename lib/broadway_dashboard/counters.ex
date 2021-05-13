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
      do_start_pipeline(pipeline)
    end
  end

  def start!(pipeline) do
    case do_start_pipeline(pipeline) do
      :ok ->
        :ok

      {:error, :pipeline_is_not_running} ->
        raise ArgumentError, "pipeline is not running: #{inspect(pipeline)}"
    end
  end

  defp do_start_pipeline(pipeline) do
    if Process.whereis(pipeline) do
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
    else
      {:error, :pipeline_is_not_running}
    end
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
    with {:ok, atomics} <- fetch_atomics(pipeline),
         {:ok, process_atomic} <- Map.fetch(atomics, name) do
      :atomics.put(process_atomic, index, value)
    else
      :error ->
        {:error, :stage_not_found}

      {:error, _} = error ->
        error
    end
  end

  def fetch_start(pipeline, name) do
    fetch_at(1, pipeline, name)
  end

  def fetch_end(pipeline, name) do
    fetch_at(2, pipeline, name)
  end

  def fetch_processing_factor(pipeline, name) do
    fetch_at(3, pipeline, name)
  end

  defp fetch_at(index, pipeline, name) do
    with {:ok, atomics} <- fetch_atomics(pipeline),
         {:ok, process_atomic} <- Map.fetch(atomics, name) do
      {:ok, :atomics.get(process_atomic, index)}
    else
      :error ->
        {:error, :stage_not_found}

      {:error, _} = error ->
        error
    end
  end

  defp fetch_atomics(pipeline) do
    {_, atomics} = :persistent_term.get({__MODULE__, pipeline}, {nil, nil})

    if atomics do
      {:ok, atomics}
    else
      {:error, :counters_not_found}
    end
  end

  def incr(pipeline, successes, fails) do
    with {:ok, counters_ref} <- fetch_counters(pipeline) do
      :counters.add(counters_ref, @successful_col, successes)
      :counters.add(counters_ref, @failed_col, fails)

      :ok
    end
  end

  def count(pipeline) do
    with {:ok, counters_ref} <- fetch_counters(pipeline) do
      successful = :counters.get(counters_ref, @successful_col)
      failed = :counters.get(counters_ref, @failed_col)

      {:ok, {successful, failed}}
    end
  end

  defp fetch_counters(pipeline) do
    {counters_ref, _} = :persistent_term.get({__MODULE__, pipeline}, {nil, nil})

    if counters_ref do
      {:ok, counters_ref}
    else
      {:error, :counters_not_found}
    end
  end
end
