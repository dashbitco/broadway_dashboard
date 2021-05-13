defmodule BroadwayDashboardTest do
  use ExUnit.Case, async: true

  import Phoenix.ConnTest
  import Phoenix.LiveViewTest
  @endpoint Phoenix.LiveDashboardTest.Endpoint

  test "menu_link/2" do
    link = "https://hexdocs.pm/broadway_dashboard"

    assert {:disabled, "Broadway pipelines", ^link} =
             BroadwayDashboard.menu_link(
               %{pipelines: []},
               %{}
             )

    assert {:ok, "Broadway pipelines"} =
             BroadwayDashboard.menu_link(
               %{pipelines: [Module]},
               %{}
             )
  end

  test "redirects to the first pipeline if no pipeline is provided" do
    {:error, {:live_redirect, %{to: "/dashboard/broadway?nav=Elixir.Demo.Pipeline"}}} =
      live(build_conn(), "/dashboard/broadway")
  end

  test "redirects to the first pipeline if pipeline provided does not exist" do
    {:error, {:live_redirect, %{to: "/dashboard/broadway?nav=Elixir.Demo.Pipeline"}}} =
      live(build_conn(), "/dashboard/broadway?nav=Elixir.IDontExist")
  end

  test "redirects to the first pipeline if no pipeline is provided keeping node" do
    base_path = URI.encode("/dashboard/#{node()}/broadway", &(&1 != ?@))

    path_with_node_and_pipeline = "#{base_path}?nav=Elixir.Demo.Pipeline"

    {:error, {:live_redirect, %{to: ^path_with_node_and_pipeline}}} =
      live(build_conn(), base_path)
  end

  test "shows the pipeline" do
    {:ok, live, _} = live(build_conn(), "/dashboard/broadway?nav=Elixir.Demo.Pipeline")

    rendered = render(live)
    assert rendered =~ "Updates automatically"
    assert rendered =~ "Throughput"
    assert rendered =~ "All time"

    assert rendered =~ "prod_0"

    assert rendered =~ "proc_0"
    assert rendered =~ "proc_9"

    assert rendered =~ "default"
    assert rendered =~ "default_0"
    assert rendered =~ "default_3"

    assert rendered =~ "s3"
    assert rendered =~ "s3_0"
    assert rendered =~ "s3_2"

    assert has_element?(live, ".banner-card-value", "0")
    refute has_element?(live, ".banner-card-value", "1")

    # Send a message
    ref = Broadway.test_message(Demo.Pipeline, "hello world")
    assert_receive {:ack, ^ref, [_successful], []}

    # Ensure the page updates it's state
    send(live.pid, {:refresh_stats, Demo.Pipeline})

    assert has_element?(live, ".banner-card-value", "1")
  end

  test "renders an error message when pipeline does not exist" do
    {:ok, live, _} = live(build_conn(), "/dashboard/broadway?nav=Elixir.MyDummy")

    rendered = render(live)

    assert rendered =~ "This pipeline is not available for this node."
  end
end
