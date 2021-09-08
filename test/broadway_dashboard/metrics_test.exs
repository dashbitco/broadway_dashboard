defmodule BroadwayDashboard.MetricsTest do
  use ExUnit.Case, async: false

  alias BroadwayDashboard.Metrics
  import BroadwayDashboard.BroadwaySupport

  @registry_name BroadwayDashboardTestRegistry

  describe "subscribe a process to a pipeline and ask it to refresh stats" do
    test "atom name" do
      broadway = start_linked_dummy_pipeline()
      subscribe_and_test(broadway)
    end

    test "via name" do
      broadway = start_linked_dummy_pipeline({:via, Registry, {@registry_name, :metrics_test}})
      subscribe_and_test(broadway)
    end

    defp subscribe_and_test(broadway) do
      server_name = Metrics.server_name(broadway)

      me = self()

      proc =
        spawn_link(fn ->
          receive do
            {:update_pipeline, payload} ->
              send(me, {:refreshed, payload})
          end
        end)

      {:ok, _} =
        start_supervised({Metrics, [pipeline: broadway, name: server_name]}, id: server_name)

      assert {:ok, _payload} = Metrics.listen(node(), proc, broadway)

      send(server_name, :refresh)

      assert_receive {:refreshed, payload}
      assert payload.pipeline == broadway

      :ok = Broadway.stop(broadway)
    end
  end

  test "returns error if pipeline is not running" do
    broadway = new_unique_name()

    proc =
      spawn_link(fn ->
        receive do
          _ -> :ok
        end
      end)

    assert {:error, :pipeline_not_found} = Metrics.listen(node(), proc, broadway)
  end

  test "restart counters when pipeline is restarted" do
    broadway = start_linked_dummy_pipeline()
    server_name = Metrics.server_name(broadway)

    proc =
      spawn_link(fn ->
        receive do
          {:update_pipeline, %{pipeline: ^broadway}} ->
            :ok
        end
      end)

    {:ok, metrics} =
      start_supervised({Metrics, [pipeline: broadway, name: server_name]}, id: server_name)

    {:ok, _payload} = Metrics.listen(node(), proc, broadway)
    counters = :sys.get_state(metrics).counters

    assert :ok = Metrics.ensure_counters_restarted(broadway)

    assert counters != :sys.get_state(metrics).counters
  end

  describe "shutdown server when there is no listener" do
    test "atom name" do
      broadway = start_linked_dummy_pipeline()
      listen_shutdown_test(broadway)
    end

    test "via name" do
      broadway = start_linked_dummy_pipeline({:via, Registry, {@registry_name, :metrics_test}})
      listen_shutdown_test(broadway)
    end

    defp listen_shutdown_test(broadway) do
      server_name = Metrics.server_name(broadway)

      me = self()

      proc =
        spawn_link(fn ->
          receive do
            {:update_pipeline, %{pipeline: ^broadway}} ->
              send(me, :refreshed)
              :ok
          end
        end)

      {:ok, pid} =
        start_supervised({Metrics, [pipeline: broadway, name: server_name, interval: 10]},
          id: server_name
        )

      {:ok, _payload} = Metrics.listen(node(), proc, broadway)

      assert_receive :refreshed
      Process.sleep(10)

      refute Process.alive?(proc)

      # Wait for shutdown timer
      Process.sleep(100)

      refute Process.alive?(pid)

      :ok = Broadway.stop(broadway)
    end
  end
end
