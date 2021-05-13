defmodule BroadwayDashboard.MetricsTest do
  use ExUnit.Case, async: false

  alias BroadwayDashboard.{Counters, Metrics}
  import BroadwayDashboard.BroadwaySupport

  test "subscribe a process to a pipeline and ask it to refresh stats" do
    broadway = start_linked_dummy_pipeline()

    me = self()

    proc =
      spawn_link(fn ->
        receive do
          {:refresh_stats, ^broadway} ->
            send(me, :refreshed)
        end
      end)

    assert :ok = Metrics.listen(node(), proc, broadway)

    send(Metrics, :refresh)

    assert_receive :refreshed

    assert {:error, :pipeline_not_found} = Metrics.listen(node(), proc, IDontExist)
  end

  test "restart counters when pipeline is restarted" do
    broadway = start_linked_dummy_pipeline()

    proc =
      spawn_link(fn ->
        receive do
          {:refresh_stats, ^broadway} ->
            :ok
        end
      end)

    assert :ok = Metrics.listen(node(), proc, broadway)

    :ok = Counters.incr(broadway, 1200, 1)

    assert :ok = Metrics.ensure_counters_restarted(broadway)

    assert {:ok, {0, 0}} = Counters.count(broadway)
  end
end
