defmodule BroadwayDashboard.PipelineGraphComponentTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest
  @endpoint Phoenix.LiveDashboardTest.Endpoint

  alias BroadwayDashboard.LiveDashboard.PipelineGraphComponent
  alias BroadwayDashboard.LiveDashboard.PipelineGraphComponent.{Layer, Node}

  test "renders a basic pipeline" do
    title = "my pipeline"
    hint = "a Broadway pipeline represented as a graph"
    graph = build_layers()

    content =
      render_component(PipelineGraphComponent,
        graph: graph,
        hint: hint,
        title: title
      )

    assert content =~ hint
    assert content =~ title

    assert content =~ "<line"
    assert content =~ "<text"

    fragment = Floki.parse_fragment!(content)

    assert length(Floki.find(fragment, ".broadway-dashboard circle")) == 3
  end

  defp build_layers do
    %Layer{
      children: [
        %Layer{
          level: 1,
          nodes: [
            %Node{
              data: %{
                detail: 0,
                label: "proc_0",
                show_detail?: true
              },
              level: 0
            },
            %Node{
              children: [],
              data: %{
                detail: 0,
                label: "proc_1",
                show_detail?: true
              },
              level: 0
            }
          ],
        }
      ],
      level: 0,
      max: 0.5,
      min: -0.5,
      nodes: [
        %Node{
          children: [],
          data: %{
            detail: 0,
            label: "prod_0",
            show_detail?: false
          },
          level: 0
        }
      ]
    }
  end
end
