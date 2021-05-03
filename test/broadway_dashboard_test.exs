defmodule BroadwayDashboardTest do
  use ExUnit.Case, async: true

  import Phoenix.ConnTest
  import Phoenix.LiveViewTest
  @endpoint Phoenix.LiveDashboardTest.Endpoint

  test "menu_link/2" do
    assert :skip =
             BroadwayDashboard.menu_link(%{pipelines: [Module]}, %{dashboard_running?: false})

    link = "https://hexdocs.pm/broadway_dashboard"

    assert {:disabled, "Broadway pipelines", ^link} =
             BroadwayDashboard.menu_link(
               %{pipelines: []},
               %{dashboard_running?: true}
             )

    assert {:ok, "Broadway pipelines"} =
             BroadwayDashboard.menu_link(
               %{pipelines: [Module]},
               %{dashboard_running?: true}
             )
  end

  test "redirects to the first pipeline if no pipeline is provided" do
    {:error, {:live_redirect, %{to: "/dashboard/broadway?nav=Elixir.Demo.Pipeline"}}} =
      live(build_conn(), "/dashboard/broadway")
  end
end
