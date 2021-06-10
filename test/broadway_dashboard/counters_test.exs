defmodule BroadwayDashboard.CountersTest do
  use ExUnit.Case, async: true

  alias BroadwayDashboard.Counters

  test "build/1 builds counters with a topology without batchers" do
    topology = [
      producers: [%{name: :default, concurrency: 1}],
      processors: [%{name: :default, concurrency: 40}],
      batchers: []
    ]

    assert %Counters{stages: 40, counters: counters, atomics: atomics, batchers_positions: %{}} =
             Counters.build(topology)

    assert %{size: 2} = :counters.info(counters)
    assert %{size: 120} = :atomics.info(atomics)
  end

  test "build/1 builds counters with a topology with batchers" do
    topology = [
      producers: [%{name: :default, concurrency: 1}],
      processors: [%{name: :default, concurrency: 40}],
      batchers: [
        %{name: :default, batcher_key: :default, concurrency: 5},
        %{name: :s3, batcher_key: :s3, concurrency: 3}
      ]
    ]

    assert %Counters{stages: 50, counters: counters, atomics: atomics, batchers_positions: pos} =
             Counters.build(topology)

    assert %{size: 2} = :counters.info(counters)
    assert %{size: 150} = :atomics.info(atomics)

    assert %{default: 41, s3: 47} == pos
  end

  test "incr/3 increments successes and failures" do
    ref = :counters.new(2, [:write_concurrency])
    counters = %Counters{counters: ref}

    assert :ok = Counters.incr(counters, 15, 1)
    assert :counters.get(ref, 1) == 15
    assert :counters.get(ref, 2) == 1
  end

  test "put_processor_start/3 sets the start time of a processor" do
    topology = [
      producers: [%{name: :default, concurrency: 1}],
      processors: [%{name: :default, concurrency: 40}],
      batchers: []
    ]

    counters = Counters.build(topology)
    start = System.monotonic_time()

    assert :ok = Counters.put_processor_start(counters, 0, start)
    assert :atomics.get(counters.atomics, 1) == start

    assert :ok = Counters.put_processor_start(counters, 19, start)
    assert :atomics.get(counters.atomics, 20) == start

    assert :ok = Counters.put_processor_start(counters, 39, start)
    assert :atomics.get(counters.atomics, 40) == start
  end

  test "put_processor_end/3 sets the end time of a processor" do
    topology = [
      producers: [%{name: :default, concurrency: 1}],
      processors: [%{name: :default, concurrency: 40}],
      batchers: []
    ]

    counters = Counters.build(topology)
    initial_pos = counters.stages
    end_time = System.monotonic_time()

    assert :ok = Counters.put_processor_end(counters, 0, end_time)
    assert :atomics.get(counters.atomics, initial_pos + 1) == end_time

    assert :ok = Counters.put_processor_end(counters, 19, end_time)
    assert :atomics.get(counters.atomics, initial_pos + 20) == end_time

    assert :ok = Counters.put_processor_end(counters, 39, end_time)
    assert :atomics.get(counters.atomics, initial_pos + 40) == end_time
  end

  test "put_processor_workload/3 sets the processing workload of a processor" do
    topology = [
      producers: [%{name: :default, concurrency: 1}],
      processors: [%{name: :default, concurrency: 40}],
      batchers: []
    ]

    counters = Counters.build(topology)
    initial_pos = counters.stages * 2
    workload = 80

    assert :ok = Counters.put_processor_workload(counters, 0, workload)
    assert :atomics.get(counters.atomics, initial_pos + 1) == workload

    assert :ok = Counters.put_processor_workload(counters, 19, workload)
    assert :atomics.get(counters.atomics, initial_pos + 20) == workload

    assert :ok = Counters.put_processor_workload(counters, 39, workload)
    assert :atomics.get(counters.atomics, initial_pos + 40) == workload
  end

  test "get_processor_start/2 returns the start time of a processor" do
    topology = [
      producers: [%{name: :default, concurrency: 1}],
      processors: [%{name: :default, concurrency: 40}],
      batchers: []
    ]

    counters = Counters.build(topology)
    start = System.monotonic_time()

    Counters.put_processor_start(counters, 0, start)
    assert {:ok, ^start} = Counters.fetch_processor_start(counters, 0)

    Counters.put_processor_start(counters, 19, start)
    assert {:ok, ^start} = Counters.fetch_processor_start(counters, 19)

    Counters.put_processor_start(counters, 39, start)
    assert {:ok, ^start} = Counters.fetch_processor_start(counters, 39)
  end

  test "get_processor_end/2 returns the end time of a processor" do
    topology = [
      producers: [%{name: :default, concurrency: 1}],
      processors: [%{name: :default, concurrency: 40}],
      batchers: []
    ]

    counters = Counters.build(topology)
    end_time = System.monotonic_time()

    Counters.put_processor_end(counters, 0, end_time)
    assert {:ok, ^end_time} = Counters.fetch_processor_end(counters, 0)

    Counters.put_processor_end(counters, 19, end_time)
    assert {:ok, ^end_time} = Counters.fetch_processor_end(counters, 19)

    Counters.put_processor_end(counters, 39, end_time)
    assert {:ok, ^end_time} = Counters.fetch_processor_end(counters, 39)
  end

  test "get_processor_workload/2 returns the end time of a processor" do
    topology = [
      producers: [%{name: :default, concurrency: 1}],
      processors: [%{name: :default, concurrency: 40}],
      batchers: []
    ]

    counters = Counters.build(topology)
    end_time = System.monotonic_time()

    Counters.put_processor_workload(counters, 0, end_time)
    assert {:ok, ^end_time} = Counters.fetch_processor_workload(counters, 0)

    Counters.put_processor_workload(counters, 19, end_time)
    assert {:ok, ^end_time} = Counters.fetch_processor_workload(counters, 19)

    Counters.put_processor_workload(counters, 39, end_time)
    assert {:ok, ^end_time} = Counters.fetch_processor_workload(counters, 39)
  end

  test "put_batcher_start/3 sets the start time for a batcher" do
    proc_concurrency = 40

    topology = [
      producers: [%{name: :default, concurrency: 1}],
      processors: [%{name: :default, concurrency: proc_concurrency}],
      batchers: [
        %{name: :default, batcher_key: :default, concurrency: 5},
        %{name: :s3, batcher_key: :s3, concurrency: 3}
      ]
    ]

    counters = Counters.build(topology)
    start = System.monotonic_time()

    assert :ok = Counters.put_batcher_start(counters, :default, start)
    assert :atomics.get(counters.atomics, proc_concurrency + 1) == start

    assert :ok = Counters.put_batcher_start(counters, :s3, start)
    # This is 7 because it's 1 from default, + 5 batch processors from default, + 1 s3 batcher
    assert :atomics.get(counters.atomics, proc_concurrency + 7) == start

    assert {:error, :batcher_position_not_found} =
             Counters.put_batcher_start(counters, :sqs, start)
  end

  test "put_batcher_end/3 sets the end time for a batcher" do
    proc_concurrency = 40

    topology = [
      producers: [%{name: :default, concurrency: 1}],
      processors: [%{name: :default, concurrency: proc_concurrency}],
      batchers: [
        %{name: :default, batcher_key: :default, concurrency: 5},
        %{name: :s3, batcher_key: :s3, concurrency: 3}
      ]
    ]

    counters = Counters.build(topology)
    end_time = System.monotonic_time()

    assert :ok = Counters.put_batcher_end(counters, :default, end_time)
    assert :atomics.get(counters.atomics, counters.stages + proc_concurrency + 1) == end_time

    assert :ok = Counters.put_batcher_end(counters, :s3, end_time)
    # This is 7 because it's 1 from default, + 5 batch processors from default, + 1 s3 batcher
    assert :atomics.get(counters.atomics, counters.stages + proc_concurrency + 7) == end_time

    assert {:error, :batcher_position_not_found} =
             Counters.put_batcher_end(counters, :sqs, end_time)
  end

  test "put_batcher_workload/3 sets the processing workload for a batcher" do
    proc_concurrency = 40

    topology = [
      producers: [%{name: :default, concurrency: 1}],
      processors: [%{name: :default, concurrency: proc_concurrency}],
      batchers: [
        %{name: :default, batcher_key: :default, concurrency: 5},
        %{name: :s3, batcher_key: :s3, concurrency: 3}
      ]
    ]

    counters = Counters.build(topology)
    workload = System.monotonic_time()

    assert :ok = Counters.put_batcher_workload(counters, :default, workload)
    assert :atomics.get(counters.atomics, counters.stages * 2 + proc_concurrency + 1) == workload

    assert :ok = Counters.put_batcher_workload(counters, :s3, workload)
    # This is 7 because it's 1 from default, + 5 batch processors from default, + 1 s3 batcher
    assert :atomics.get(counters.atomics, counters.stages * 2 + proc_concurrency + 7) == workload

    assert {:error, :batcher_position_not_found} =
             Counters.put_batcher_workload(counters, :sqs, workload)
  end

  test "get_batcher_start/2 gets the start time for a batcher" do
    proc_concurrency = 40

    topology = [
      producers: [%{name: :default, concurrency: 1}],
      processors: [%{name: :default, concurrency: proc_concurrency}],
      batchers: [
        %{name: :default, batcher_key: :default, concurrency: 5},
        %{name: :s3, batcher_key: :s3, concurrency: 3}
      ]
    ]

    counters = Counters.build(topology)
    start = System.monotonic_time()

    :ok = Counters.put_batcher_start(counters, :default, start)
    assert {:ok, ^start} = Counters.fetch_batcher_start(counters, :default)

    assert {:error, :batcher_position_not_found} = Counters.fetch_batcher_start(counters, :sqs)
  end

  test "get_batcher_end/2 gets the end time for a batcher" do
    proc_concurrency = 40

    topology = [
      producers: [%{name: :default, concurrency: 1}],
      processors: [%{name: :default, concurrency: proc_concurrency}],
      batchers: [
        %{name: :default, batcher_key: :default, concurrency: 5},
        %{name: :s3, batcher_key: :s3, concurrency: 3}
      ]
    ]

    counters = Counters.build(topology)
    end_time = System.monotonic_time()

    Counters.put_batcher_end(counters, :default, end_time)

    assert {:ok, ^end_time} = Counters.fetch_batcher_end(counters, :default)

    Counters.put_batcher_end(counters, :s3, end_time)
    assert {:ok, ^end_time} = Counters.fetch_batcher_end(counters, :s3)

    assert {:error, :batcher_position_not_found} = Counters.fetch_batcher_end(counters, :sqs)
  end

  test "get_batcher_workload/3 gets the processing workload for a batcher" do
    proc_concurrency = 40

    topology = [
      producers: [%{name: :default, concurrency: 1}],
      processors: [%{name: :default, concurrency: proc_concurrency}],
      batchers: [
        %{name: :default, batcher_key: :default, concurrency: 5},
        %{name: :s3, batcher_key: :s3, concurrency: 3}
      ]
    ]

    counters = Counters.build(topology)
    workload = System.monotonic_time()

    Counters.put_batcher_workload(counters, :default, workload)
    assert {:ok, ^workload} = Counters.fetch_batcher_workload(counters, :default)

    Counters.put_batcher_workload(counters, :s3, workload)
    assert {:ok, ^workload} = Counters.fetch_batcher_workload(counters, :s3)

    assert {:error, :batcher_position_not_found} = Counters.fetch_batcher_workload(counters, :sqs)
  end

  test "put_batch_processor_start/4 puts the value" do
    proc_concurrency = 40

    topology = [
      producers: [%{name: :default, concurrency: 1}],
      processors: [%{name: :default, concurrency: proc_concurrency}],
      batchers: [
        %{name: :default, batcher_key: :default, concurrency: 5},
        %{name: :s3, batcher_key: :s3, concurrency: 3}
      ]
    ]

    counters = Counters.build(topology)
    workload = System.monotonic_time()

    Counters.put_batch_processor_start(counters, :default, 1, workload)
    assert {:ok, ^workload} = Counters.fetch_batch_processor_start(counters, :default, 1)

    Counters.put_batch_processor_start(counters, :s3, 3, workload)
    assert {:ok, ^workload} = Counters.fetch_batch_processor_start(counters, :s3, 3)

    assert {:error, :batcher_position_not_found} =
             Counters.fetch_batch_processor_workload(counters, :sqs, 4)
  end
end
