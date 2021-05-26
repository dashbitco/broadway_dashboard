defmodule BroadwayDashboard.ListenersTest do
  use ExUnit.Case, async: true

  alias BroadwayDashboard.Listeners

  test "add/3 adds a given listeners assigned to a pipeline" do
    listener = spawn_link(fn -> :ok end)
    pipeline = ExamplePipeline

    assert %{^pipeline => pids} = Listeners.add(%{}, pipeline, listener)

    assert MapSet.equal?(pids, MapSet.new([listener]))
  end

  test "remove/2 remove the listener from pipelines" do
    listener = spawn_link(fn -> :ok end)
    pipeline = ExamplePipeline

    listeners = Listeners.add(%{}, pipeline, listener)

    assert %{^pipeline => pids} = Listeners.remove(listeners, listener)

    refute MapSet.member?(pids, listener)
  end
end
