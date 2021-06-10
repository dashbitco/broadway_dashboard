defmodule BroadwayDashboard.Counters do
  @moduledoc false

  # This represents the counters of a pipeline.
  #
  # It has a counter with two entries (for success and errors),
  # and an "atomics" with N-entries to store each stage "start",
  # "end" and "work factor".
  #
  # The "total" represents the size of stages in a pipeline.
  # So for example, if the pipeline has this config:
  #
  #   [
  #     processors: [default: [concurrency: 40],
  #     batchers: [
  #       default: [concurrency: 5],
  #       s3: [concurrency: 3]
  #     ]
  #   ]
  #
  # The total of stages is 48 + 2, the "2" being the batchers itself.
  # So we have 50 stages in this pipeline.
  # Our atomics will have the size of 50 * 3, because we need
  # to store the "start", "end" and "work factor" for each stage.
  #
  # The "batchers_positions" represents where each batcher is located
  # inside the "atomics". We do the following for the atomics positions:
  #
  # - the position of processors starts in "0".
  # - the first batcher, sorted by name, starts at the end of processors.
  # - the batch processor has the position of the batcher + its index.
  # - so the position of the next batcher is equal to the last batch
  # processor of the previous + 1.
  #
  # This way we can say where each stage is located for the "start"
  # value. For the "end" value we simply add the "total" to the found
  # position of start. And for the "work factor" we add the "total" again.

  defstruct stages: 0, counters: nil, atomics: nil, batchers_positions: %{}

  defguardp valid_processor_input?(index, value)
            when is_integer(index) and index >= 0 and is_integer(value)

  defguardp valid_batcher_input?(batcher_key, value)
            when is_atom(batcher_key) and is_integer(value)

  @doc """
  Builds a counters struct based on a Broadway `topology`.
  """
  def build(topology) do
    total =
      for {layer, details} when layer != :producers <- topology, group <- details, reduce: 0 do
        acc ->
          acc + group.concurrency + if layer == :batchers, do: 1, else: 0
      end

    [%{concurrency: start_index}] = topology[:processors]

    {_, positions} =
      Enum.reduce(topology[:batchers], {start_index + 1, %{}}, fn batcher, {index, positions} ->
        {index + batcher.concurrency + 1, Map.put(positions, batcher.batcher_key, index)}
      end)

    %__MODULE__{
      stages: total,
      batchers_positions: positions,
      counters: :counters.new(2, [:write_concurrency]),
      atomics: :atomics.new(total * 3, signed: true)
    }
  end

  def incr(%__MODULE__{} = counters, successes, failures) do
    :ok = :counters.add(counters.counters, 1, successes)
    :ok = :counters.add(counters.counters, 2, failures)
  end

  @doc """
  Returns the topology with its workload for each stage.

  The workload is a number for 0 to 100 and represent the percentage of time a
  stage is busy.

  It returns the topology along with the workload for each group of processors,
  batchers and batch processors. Producers don't have workload because we can't
  detect it from our telemetry events.
  """
  def topology_workload(%__MODULE__{} = counters, topology) do
    for {stage, groups} <- topology do
      groups =
        case stage do
          :processors ->
            [group] = groups

            workloads =
              for idx <- 0..(group.concurrency - 1) do
                {:ok, value} = get_processor_processing_factor(counters, idx)
                value
              end

            [Map.put(group, :workloads, workloads)]

          :batchers ->
            Enum.map(groups, fn group ->
              {:ok, batcher_workload} = get_batcher_processing_factor(counters, group.batcher_key)

              workloads =
                for idx <- 0..(group.concurrency - 1) do
                  {:ok, value} = get_processor_processing_factor(counters, idx)
                  value
                end

              group
              |> Map.put(:batcher_workload, batcher_workload)
              |> Map.put(:workloads, workloads)
            end)

          _ ->
            groups
        end

      {stage, groups}
    end
  end

  ## Processors

  def put_processor_start(%__MODULE__{} = counters, index, start)
      when valid_processor_input?(index, start) do
    :atomics.put(counters.atomics, index + 1, start)
  end

  def put_processor_end(%__MODULE__{} = counters, index, end_time)
      when valid_processor_input?(index, end_time) do
    :atomics.put(counters.atomics, counters.stages + index + 1, end_time)
  end

  def put_processor_processing_factor(%__MODULE__{} = counters, index, factor)
      when valid_processor_input?(index, factor) do
    :atomics.put(counters.atomics, counters.stages * 2 + index + 1, factor)
  end

  def get_processor_start(%__MODULE__{} = counters, index) when index >= 0 do
    {:ok, :atomics.get(counters.atomics, index + 1)}
  end

  def get_processor_end(%__MODULE__{} = counters, index) when index >= 0 do
    {:ok, :atomics.get(counters.atomics, counters.stages + index + 1)}
  end

  def get_processor_processing_factor(%__MODULE__{} = counters, index) when index >= 0 do
    {:ok, :atomics.get(counters.atomics, counters.stages * 2 + index + 1)}
  end

  ## Batchers

  def put_batcher_start(%__MODULE__{} = counters, batcher_key, start)
      when valid_batcher_input?(batcher_key, start) do
    with {:ok, position} <- batcher_position(counters, batcher_key) do
      :atomics.put(counters.atomics, position, start)
    end
  end

  def put_batcher_end(%__MODULE__{} = counters, batcher_key, end_time)
      when valid_batcher_input?(batcher_key, end_time) do
    with {:ok, position} <- batcher_position(counters, batcher_key) do
      :atomics.put(counters.atomics, counters.stages + position, end_time)
    end
  end

  def put_batcher_processing_factor(%__MODULE__{} = counters, batcher_key, factor)
      when valid_batcher_input?(batcher_key, factor) do
    with {:ok, position} <- batcher_position(counters, batcher_key) do
      :atomics.put(counters.atomics, counters.stages * 2 + position, factor)
    end
  end

  def get_batcher_start(%__MODULE__{} = counters, batcher_key) do
    with {:ok, position} <- batcher_position(counters, batcher_key) do
      {:ok, :atomics.get(counters.atomics, position)}
    end
  end

  def get_batcher_end(%__MODULE__{} = counters, batcher_key) do
    with {:ok, position} <- batcher_position(counters, batcher_key) do
      {:ok, :atomics.get(counters.atomics, counters.stages + position)}
    end
  end

  def get_batcher_processing_factor(%__MODULE__{} = counters, batcher_key) do
    with {:ok, position} <- batcher_position(counters, batcher_key) do
      {:ok, :atomics.get(counters.atomics, counters.stages * 2 + position)}
    end
  end

  ## Batch processors
  # TODO: test me

  def put_batch_processor_start(%__MODULE__{} = counters, batcher_key, index, start) do
    with {:ok, position} <- batcher_position(counters, batcher_key) do
      :atomics.put(counters.atomics, position + index + 1, start)
    end
  end

  def put_batch_processor_end(%__MODULE__{} = counters, batcher_key, index, end_time) do
    with {:ok, position} <- batcher_position(counters, batcher_key) do
      :atomics.put(counters.atomics, counters.stages + position + index + 1, end_time)
    end
  end

  def put_batch_processor_processing_factor(%__MODULE__{} = counters, batcher_key, index, factor) do
    with {:ok, position} <- batcher_position(counters, batcher_key) do
      :atomics.put(counters.atomics, counters.stages * 2 + position + index + 1, factor)
    end
  end

  def get_batch_processor_start(%__MODULE__{} = counters, batcher_key, index) do
    with {:ok, position} <- batcher_position(counters, batcher_key) do
      {:ok, :atomics.get(counters.atomics, position + index + 1)}
    end
  end

  def get_batch_processor_end(%__MODULE__{} = counters, batcher_key, index) do
    with {:ok, position} <- batcher_position(counters, batcher_key) do
      {:ok, :atomics.get(counters.atomics, counters.stages + position + index + 1)}
    end
  end

  def get_batch_processor_processing_factor(%__MODULE__{} = counters, batcher_key, index) do
    with {:ok, position} <- batcher_position(counters, batcher_key) do
      from = counters.stages * 2 + position + index + 1
      # IO.inspect(:atomics.get(counters.atomics, from - 2))
      {:ok, :atomics.get(counters.atomics, from)}
    end
  end

  def count(counters) do
    successful = :counters.get(counters.counters, 1)
    failed = :counters.get(counters.counters, 2)

    {:ok, {successful, failed}}
  end

  defp batcher_position(counters, batcher_key) do
    position = counters.batchers_positions[batcher_key]

    if position do
      {:ok, position}
    else
      {:error, :batcher_position_not_found}
    end
  end
end
