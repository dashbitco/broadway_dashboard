defmodule BroadwayDashboard.NewCountersTest do
  use ExUnit.Case, async: true

  alias BroadwayDashboard.NewCounters

  test "build/1 builds counters with a topology without batchers" do
    topology = [
      producers: [%{name: :default, concurrency: 1}],
      processors: [%{name: :default, concurrency: 40}],
      batchers: []
    ]

    assert %NewCounters{stages: 40, counters: counters, atomics: atomics, batchers_positions: %{}} =
             NewCounters.build(topology)

    assert %{size: 2} = :counters.info(counters)
    assert %{size: 120} = :atomics.info(atomics)
  end

  test "build/1 builds counters with a topology with batchers" do
    topology = [
      producers: [%{name: :default, concurrency: 1}],
      processors: [%{name: :default, concurrency: 40}],
      batchers: [
        %{name: :default, batcher_name: :default, concurrency: 5},
        %{name: :s3, batcher_name: :s3, concurrency: 3}
      ]
    ]

    assert %NewCounters{stages: 50, counters: counters, atomics: atomics, batchers_positions: pos} =
             NewCounters.build(topology)

    assert %{size: 2} = :counters.info(counters)
    assert %{size: 150} = :atomics.info(atomics)

    assert %{default: 41, s3: 47} == pos
  end

  test "incr/3 increments successes and failures" do
    ref = :counters.new(2, [:write_concurrency])
    counters = %NewCounters{counters: ref}

    assert :ok = NewCounters.incr(counters, 15, 1)
    assert :counters.get(ref, 1) == 15
    assert :counters.get(ref, 2) == 1
  end

  test "put_processor_start/3 sets the start time of a processor" do
    topology = [
      producers: [%{name: :default, concurrency: 1}],
      processors: [%{name: :default, concurrency: 40}],
      batchers: []
    ]

    counters = NewCounters.build(topology)
    start = System.monotonic_time()

    assert :ok = NewCounters.put_processor_start(counters, 0, start)
    assert :atomics.get(counters.atomics, 1) == start

    assert :ok = NewCounters.put_processor_start(counters, 19, start)
    assert :atomics.get(counters.atomics, 20) == start

    assert :ok = NewCounters.put_processor_start(counters, 39, start)
    assert :atomics.get(counters.atomics, 40) == start
  end

  test "put_processor_end/3 sets the end time of a processor" do
    topology = [
      producers: [%{name: :default, concurrency: 1}],
      processors: [%{name: :default, concurrency: 40}],
      batchers: []
    ]

    counters = NewCounters.build(topology)
    start_at = counters.stages
    end_time = System.monotonic_time()

    assert :ok = NewCounters.put_processor_end(counters, 0, end_time)
    assert :atomics.get(counters.atomics, start_at + 1) == end_time

    assert :ok = NewCounters.put_processor_end(counters, 19, end_time)
    assert :atomics.get(counters.atomics, start_at + 20) == end_time

    assert :ok = NewCounters.put_processor_end(counters, 39, end_time)
    assert :atomics.get(counters.atomics, start_at + 40) == end_time
  end

  test "put_processor_processing_factor/3 sets the processing factor of a processor" do
    topology = [
      producers: [%{name: :default, concurrency: 1}],
      processors: [%{name: :default, concurrency: 40}],
      batchers: []
    ]

    counters = NewCounters.build(topology)
    start_at = counters.stages * 2
    factor = 80

    assert :ok = NewCounters.put_processor_processing_factor(counters, 0, factor)
    assert :atomics.get(counters.atomics, start_at + 1) == factor

    assert :ok = NewCounters.put_processor_processing_factor(counters, 19, factor)
    assert :atomics.get(counters.atomics, start_at + 20) == factor

    assert :ok = NewCounters.put_processor_processing_factor(counters, 39, factor)
    assert :atomics.get(counters.atomics, start_at + 40) == factor
  end
end
