defmodule BroadwayDashboard.MetricsTest do
  use ExUnit.Case, async: false

  alias BroadwayDashboard.{Counters, Metrics}
  import BroadwayDashboard.BroadwaySupport

  test "subscribe a process to a pipeline and ask it to refresh stats" do
    broadway = start_linked_dummy_pipeline()
    server_name = Metrics.server_name(broadway)

    me = self()

    proc =
      spawn_link(fn ->
        receive do
          {:refresh_stats, ^broadway} ->
            send(me, :refreshed)
        end
      end)

    {:ok, _} =
      start_supervised({Metrics, [pipeline: broadway, name: server_name]}, id: server_name)

    assert :ok = Metrics.listen(node(), proc, broadway)

    send(server_name, :refresh)

    assert_receive :refreshed
  end

  test "restart counters when pipeline is restarted" do
    broadway = start_linked_dummy_pipeline()
    server_name = Metrics.server_name(broadway)

    proc =
      spawn_link(fn ->
        receive do
          {:refresh_stats, ^broadway} ->
            :ok
        end
      end)

    {:ok, _} =
      start_supervised({Metrics, [pipeline: broadway, name: server_name]}, id: server_name)

    :ok = Metrics.listen(node(), proc, broadway)

    :ok = Counters.incr(broadway, 1200, 1)
    {:ok, {1200, 1}} = Counters.count(broadway)

    assert :ok = Metrics.ensure_counters_restarted(broadway)

    assert {:ok, {0, 0}} = Counters.count(broadway)
  end

  test "shutdown server when there is no listener" do
    broadway = start_linked_dummy_pipeline()
    server_name = Metrics.server_name(broadway)

    me = self()

    proc =
      spawn_link(fn ->
        receive do
          {:refresh_stats, ^broadway} ->
            send(me, :refreshed)
            :ok
        end
      end)

    {:ok, pid} =
      start_supervised({Metrics, [pipeline: broadway, name: server_name, interval: 10]},
        id: server_name
      )

    :ok = Metrics.listen(node(), proc, broadway)

    assert_receive :refreshed
    refute Process.alive?(proc)

    # Wait for shutdown timer
    Process.sleep(100)

    refute Process.alive?(pid)
  end
end
