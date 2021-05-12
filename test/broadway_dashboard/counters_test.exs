defmodule BroadwayDashboard.CountersTest do
  use ExUnit.Case, async: true

  alias BroadwayDashboard.Counters

  defmodule Forwarder do
    use Broadway

    def handle_message(:default, message, %{test_pid: test_pid}) do
      send(test_pid, {:message_handled, message.data})
      message
    end

    def handle_batch(batcher, messages, _, %{test_pid: test_pid}) do
      send(test_pid, {:batch_handled, batcher, messages})
      messages
    end
  end

  defp new_unique_name do
    :"Elixir.Broadway#{System.unique_integer([:positive, :monotonic])}"
  end

  test "start/1 starts counters for a pipeline" do
    broadway = new_unique_name()

    Broadway.start_link(Forwarder,
      name: broadway,
      context: %{test_pid: self()},
      producer: [module: {Broadway.DummyProducer, []}],
      processors: [default: [concurrency: 10]],
      batchers: [default: [concurrency: 2], s3: [concurrency: 3]]
    )

    assert :ok = Counters.start(broadway)
    assert :persistent_term.get({Counters, broadway})

    assert :already_started = Counters.start(broadway)
  end

  test "start/1 returns error if pipeline is not running" do
    broadway = new_unique_name()

    assert {:error, :pipeline_is_not_running} = Counters.start(broadway)
  end

  test "start!/1 rebuild counters for a pipeline if exists" do
    broadway = new_unique_name()

    Broadway.start_link(Forwarder,
      name: broadway,
      context: %{test_pid: self()},
      producer: [module: {Broadway.DummyProducer, []}],
      processors: [default: [concurrency: 10]],
      batchers: [default: [concurrency: 2], s3: [concurrency: 3]]
    )

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

  test "put_start/3 stores the last started time for a stage" do
    broadway = new_unique_name()

    Broadway.start_link(Forwarder,
      name: broadway,
      context: %{test_pid: self()},
      producer: [module: {Broadway.DummyProducer, []}],
      processors: [default: [concurrency: 10]],
      batchers: [default: [concurrency: 2], s3: [concurrency: 3]]
    )

    :ok = Counters.start(broadway)

    topology = Broadway.topology(broadway)
    [%{batcher_name: default_batcher} | _] = topology[:batchers]

    assert :ok = Counters.put_start(broadway, default_batcher, 42000)

    assert Counters.get_start(broadway, default_batcher) == 42000

    assert {:error, :stage_not_found} = Counters.put_start(broadway, Module, 10000)
  end
end
