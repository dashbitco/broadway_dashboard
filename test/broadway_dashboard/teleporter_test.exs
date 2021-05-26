defmodule BroadwayDashboard.TeleporterTest do
  use ExUnit.Case, async: false

  import BroadwayDashboard.DistributionSupport

  setup do
    setup_support_project!("dummy_broadway_app.exs")
  end

  @tag :distribution
  test "teleport_metrics_code/1 to a running node", %{node_name: node_name} do
    Node.connect(node_name)
    assert :ok = BroadwayDashboard.Teleporter.teleport_metrics_code(node_name)
  end

  @tag :distribution
  test "teleport_metrics_code/1 to a node that is down" do
    host = current_hostname!()

    assert {:error, {:badrpc, _reason}} =
             BroadwayDashboard.Teleporter.teleport_metrics_code(:"foo@#{host}")
  end
end
