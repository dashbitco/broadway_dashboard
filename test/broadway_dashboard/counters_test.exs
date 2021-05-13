defmodule BroadwayDashboard.CountersTest do
  use ExUnit.Case, async: true
  import BroadwayDashboard.BroadwaySupport

  alias BroadwayDashboard.Counters

  test "start/1 starts counters for a pipeline" do
    broadway = start_linked_dummy_pipeline()

    assert :ok = Counters.start(broadway)
    assert :persistent_term.get({Counters, broadway})

    assert :already_started = Counters.start(broadway)
  end

  test "start/1 returns error if pipeline is not running" do
    broadway = new_unique_name()

    assert {:error, :pipeline_is_not_running} = Counters.start(broadway)
  end

  test "start!/1 rebuild counters for a pipeline if exists" do
    broadway = start_linked_dummy_pipeline()

    assert :ok = Counters.start!(broadway)
    assert :persistent_term.get({Counters, broadway})

    assert :ok = Counters.start!(broadway)
  end

  test "start!/1 raises if pipeline is not running" do
    broadway = new_unique_name()

    assert_raise ArgumentError, "pipeline is not running: #{inspect(broadway)}", fn ->
      Counters.start!(broadway)
    end
  end

  test "erase/1 erases data from persistent_term" do
    broadway = start_linked_dummy_pipeline()

    Counters.start!(broadway)

    assert Counters.erase(broadway)
    refute :persistent_term.get({Counters, broadway}, false)
  end

  test "put_start/3 stores the last started time for a stage" do
    broadway = start_linked_dummy_pipeline()

    :ok = Counters.start(broadway)

    topology = Broadway.topology(broadway)
    [%{batcher_name: default_batcher} | _] = topology[:batchers]

    assert :ok = Counters.put_start(broadway, default_batcher, 42000)

    assert {:ok, 42000} = Counters.fetch_start(broadway, default_batcher)

    assert {:error, :stage_not_found} = Counters.put_start(broadway, Module, 10000)
  end

  test "fetch_start/2 returns the last start time of a stage" do
    broadway = start_linked_dummy_pipeline()

    :ok = Counters.start(broadway)

    topology = Broadway.topology(broadway)
    [%{batcher_name: default_batcher} | _] = topology[:batchers]

    assert {:ok, 0} = Counters.fetch_start(broadway, default_batcher)

    now = System.monotonic_time()

    assert :ok = Counters.put_start(broadway, default_batcher, now)

    assert {:ok, ^now} = Counters.fetch_start(broadway, default_batcher)
    assert {:error, :stage_not_found} = Counters.fetch_start(broadway, Module)
  end

  test "put_end/3 stores the last ended time for a stage" do
    broadway = start_linked_dummy_pipeline()

    :ok = Counters.start(broadway)

    topology = Broadway.topology(broadway)
    [%{batcher_name: default_batcher} | _] = topology[:batchers]

    assert :ok = Counters.put_end(broadway, default_batcher, 42000)

    assert {:ok, 42000} = Counters.fetch_end(broadway, default_batcher)

    assert {:error, :stage_not_found} = Counters.put_end(broadway, Module, 10000)
  end

  test "fetch_end/2 returns the last end time of a stage" do
    broadway = start_linked_dummy_pipeline()

    :ok = Counters.start(broadway)

    topology = Broadway.topology(broadway)
    [%{batcher_name: default_batcher} | _] = topology[:batchers]

    assert {:ok, 0} = Counters.fetch_end(broadway, default_batcher)

    now = System.monotonic_time()

    assert :ok = Counters.put_end(broadway, default_batcher, now)

    assert {:ok, ^now} = Counters.fetch_end(broadway, default_batcher)
    assert {:error, :stage_not_found} = Counters.fetch_end(broadway, Module)
  end

  test "put_processing_factor/3 stores the last ended time for a stage" do
    broadway = start_linked_dummy_pipeline()

    :ok = Counters.start(broadway)

    topology = Broadway.topology(broadway)
    [%{batcher_name: default_batcher} | _] = topology[:batchers]

    assert :ok = Counters.put_processing_factor(broadway, default_batcher, 42000)

    assert {:ok, 42000} = Counters.fetch_processing_factor(broadway, default_batcher)

    assert {:error, :stage_not_found} = Counters.put_processing_factor(broadway, Module, 10000)
  end

  test "fetch_processing_factor/2 returns the last end time of a stage" do
    broadway = start_linked_dummy_pipeline()

    :ok = Counters.start(broadway)

    topology = Broadway.topology(broadway)
    [%{batcher_name: default_batcher} | _] = topology[:batchers]

    assert {:ok, 0} = Counters.fetch_processing_factor(broadway, default_batcher)

    now = System.monotonic_time()

    assert :ok = Counters.put_processing_factor(broadway, default_batcher, now)

    assert {:ok, ^now} = Counters.fetch_processing_factor(broadway, default_batcher)
    assert {:error, :stage_not_found} = Counters.fetch_processing_factor(broadway, Module)
  end

  test "incr/3 increments successes and failures" do
    broadway = start_linked_dummy_pipeline()

    :ok = Counters.start(broadway)

    assert :ok = Counters.incr(broadway, 5, 0)
    assert {:ok, {5, 0}} = Counters.count(broadway)

    assert :ok = Counters.incr(broadway, 0, 0)
    assert {:ok, {5, 0}} = Counters.count(broadway)

    assert :ok = Counters.incr(broadway, 0, 10)
    assert {:ok, {5, 10}} = Counters.count(broadway)
  end
end
