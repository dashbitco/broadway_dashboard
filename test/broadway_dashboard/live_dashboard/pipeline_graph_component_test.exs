defmodule BroadwayDashboard.PipelineGraphComponentTest do
  use ExUnit.Case, async: true

  # TODO: move this test to PhoenixLiveDashboard project
  #
  import Phoenix.LiveViewTest
  @endpoint Phoenix.LiveDashboardTest.Endpoint

  alias BroadwayDashboard.LiveDashboard.PipelineGraphComponent

  test "renders a basic pipeline" do
    title = "my pipeline"
    hint = "a Broadway pipeline represented as a graph"
    layers = build_layers()

    content =
      render_component(PipelineGraphComponent,
        layers: layers,
        hint: hint,
        title: title
      )

    assert content =~ hint
    assert content =~ title

    # TODO: draw lines
    # assert content =~ "<line"
    assert content =~ "<text"

    fragment = Floki.parse_fragment!(content)

    assert length(Floki.find(fragment, ".broadway-dashboard circle")) == 2
  end

  defp build_layers do
    [
      [
        %{
          id: MyPipeline.Broadway.Producer_0,
          data: %{
            detail: 0,
            label: "prod_0",
            show_detail?: false
          },
          children: [MyPipeline.Broadway.Processor_default_0]
        }
      ],
      [
        %{
          id: MyPipeline.Broadway.Processor_default_0,
          data: %{
            detail: 0,
            label: "proc_1"
          },
          children: []
        }
      ]
    ]
  end
end
