defmodule BroadwayDashboardTest do
  use ExUnit.Case, async: false

  import Phoenix.ConnTest
  import Phoenix.LiveViewTest
  @endpoint Phoenix.LiveDashboardTest.Endpoint

  alias BroadwayDashboard.Metrics

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
    start_supervised!(Demo.Pipeline)

    {:ok, live, _} = live(build_conn(), "/dashboard/broadway?nav=Elixir.Demo.Pipeline")

    rendered = render(live)
    assert rendered =~ "Updates automatically"
    assert rendered =~ "Throughput"
    assert rendered =~ "All time"

    assert rendered =~ "prod_0"

    assert rendered =~ "proc_0"
    assert rendered =~ "proc_9"

    assert rendered =~ "default"
    assert rendered =~ "proc_0"
    assert rendered =~ "proc_3"

    assert rendered =~ "s3"
    assert rendered =~ "proc_0"
    assert rendered =~ "proc_2"

    assert has_element?(live, ".banner-card-value", "0")
    refute has_element?(live, ".banner-card-value", "1")

    # Send a message
    ref = Broadway.test_message(Demo.Pipeline, "hello world")
    assert_receive {:ack, ^ref, [_successful], []}

    # Ensure the page updates it's state
    server_name = Metrics.server_name(Demo.Pipeline)
    send(server_name, :refresh)

    # ensure it renders again
    render(live)

    assert has_element?(live, ".banner-card-value", "1")
  end

  test "renders an error message when pipeline does not exist" do
    {:ok, live, _} = live(build_conn(), "/dashboard/broadway?nav=Elixir.MyDummy")

    rendered = render(live)

    assert rendered =~ "This pipeline is not available for this node."
  end

  @tag distribution: true
  test "renders an error message when broadway is outdated on remote node" do
    node_info =
      BroadwayDashboard.DistributionSupport.setup_support_project!(
        "dummy_broadway_app_with_outdated_broadway.exs"
      )

    remote_node = node_info[:node_name]

    Node.connect(remote_node)

    base_path = URI.encode("/dashboard/#{remote_node}/broadway", &(&1 != ?@))
    {:ok, live, _} = live(build_conn(), "#{base_path}?nav=Elixir.MyDummyOutdated")

    rendered = render(live)

    assert rendered =~ "Broadway is outdated on remote node."
  end
end
