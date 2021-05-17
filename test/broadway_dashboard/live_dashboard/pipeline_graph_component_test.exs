defmodule BroadwayDashboard.PipelineGraphComponentTest do
  use ExUnit.Case, async: true

  # TODO: move this test to PhoenixLiveDashboard project
  #
  import Phoenix.LiveViewTest
  @endpoint Phoenix.LiveDashboardTest.Endpoint

  alias BroadwayDashboard.LiveDashboard.PipelineGraphComponent
  alias BroadwayDashboard.LiveDashboard.PipelineGraphComponent.{Layer, Node}

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

    assert content =~ "<line"
    assert content =~ "<text"

    fragment = Floki.parse_fragment!(content)

    assert length(Floki.find(fragment, ".broadway-dashboard circle")) == 3
  end

  test "calculate positions and levels" do
    layers = build_complex_layers()

    # It's the root and there is one node
    assert %Layer{
             pos: 1.5,
             min: -0.5,
             max: 3.5,
             level: 0,
             nodes: [producer],
             children: [processors_layer]
           } = PipelineGraphComponent.calc_span(layers)

    assert %Node{pos: 0.0, min: 0.0, max: 0.0} = producer

    assert %Layer{
             pos: 1.5,
             level: 1,
             min: 0.0,
             max: 0.0,
             nodes: processors,
             children: [default_batch_layer, s3_batch_layer]
           } = processors_layer

    assert Enum.all?(processors, fn p -> {p.min, p.max, p.pos} == {0.0, 0.0, 0.0} end)

    assert %Layer{
             pos: 0.5,
             level: 2,
             min: 0.0,
             max: 0.0,
             nodes: [default],
             children: default_batch_processors
           } = default_batch_layer

    assert %Node{pos: 0.0, min: 0.0, max: 0.0} = default

    assert %Layer{
             pos: 2.5,
             level: 2,
             min: 0.0,
             max: 0.0,
             nodes: [s3],
             children: s3_batch_processors
           } = s3_batch_layer

    assert %Node{pos: 0.0, min: 0.0, max: 0.0} = s3

    assert [
             %Node{
               children: [],
               level: 3,
               max: 0.0,
               min: 0.0,
               pos: 0
             },
             %Node{
               children: [],
               level: 3,
               max: 0.0,
               min: 0.0,
               pos: 1
             }
           ] = default_batch_processors

    assert [
             %Node{
               children: [],
               level: 3,
               max: 0.0,
               min: 0.0,
               pos: 2
             },
             %Node{
               children: [],
               level: 3,
               max: 0.0,
               min: 0.0,
               pos: 3
             }
           ] = s3_batch_processors
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
          ]
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

  defp build_complex_layers do
    %Layer{
      children: [
        %Layer{
          children: [
            %Layer{
              children: [
                %Node{
                  children: [],
                  data: %{
                    detail: 0,
                    label: "default_0",
                    name: Broadway3.Broadway.BatchProcessor_default_0,
                    show_detail?: true
                  },
                  level: 0,
                  max: 0.0,
                  min: 0.0,
                  pos: 0.0
                },
                %Node{
                  children: [],
                  data: %{
                    detail: 0,
                    label: "default_1",
                    name: Broadway3.Broadway.BatchProcessor_default_1,
                    show_detail?: true
                  },
                  level: 0,
                  max: 0.0,
                  min: 0.0,
                  pos: 0.0
                }
              ],
              level: 0,
              max: 0.0,
              min: 0.0,
              nodes: [
                %Node{
                  children: [],
                  data: %{
                    detail: 0,
                    label: "default",
                    name: Broadway3.Broadway.Batcher_default,
                    show_detail?: true
                  },
                  level: 0,
                  max: 0.0,
                  min: 0.0,
                  pos: 0.0
                }
              ],
              pos: 0.0
            },
            %Layer{
              children: [
                %Node{
                  children: [],
                  data: %{
                    detail: 0,
                    label: "s3_0",
                    name: Broadway3.Broadway.BatchProcessor_s3_0,
                    show_detail?: true
                  },
                  level: 0,
                  max: 0.0,
                  min: 0.0,
                  pos: 0.0
                },
                %Node{
                  children: [],
                  data: %{
                    detail: 0,
                    label: "s3_1",
                    name: Broadway3.Broadway.BatchProcessor_s3_1,
                    show_detail?: true
                  },
                  level: 0,
                  max: 0.0,
                  min: 0.0,
                  pos: 0.0
                }
              ],
              level: 0,
              max: 0.0,
              min: 0.0,
              nodes: [
                %Node{
                  children: [],
                  data: %{
                    detail: 0,
                    label: "s3",
                    name: Broadway3.Broadway.Batcher_s3,
                    show_detail?: true
                  },
                  level: 0,
                  max: 0.0,
                  min: 0.0,
                  pos: 0.0
                }
              ],
              pos: 0.0
            }
          ],
          level: 0,
          max: 0.0,
          min: 0.0,
          nodes: [
            %Node{
              children: [],
              data: %{
                detail: 0,
                label: "proc_0",
                name: Broadway3.Broadway.Processor_default_0,
                show_detail?: true
              },
              level: 0,
              max: 0.0,
              min: 0.0,
              pos: 0.0
            },
            %Node{
              children: [],
              data: %{
                detail: 0,
                label: "proc_1",
                name: Broadway3.Broadway.Processor_default_1,
                show_detail?: true
              },
              level: 0,
              max: 0.0,
              min: 0.0,
              pos: 0.0
            },
            %Node{
              children: [],
              data: %{
                detail: 0,
                label: "proc_2",
                name: Broadway3.Broadway.Processor_default_2,
                show_detail?: true
              },
              level: 0,
              max: 0.0,
              min: 0.0,
              pos: 0.0
            },
            %Node{
              children: [],
              data: %{
                detail: 0,
                label: "proc_3",
                name: Broadway3.Broadway.Processor_default_3,
                show_detail?: true
              },
              level: 0,
              max: 0.0,
              min: 0.0,
              pos: 0.0
            }
          ],
          pos: 0.0
        }
      ],
      level: 0,
      max: 0.0,
      min: 0.0,
      nodes: [
        %Node{
          children: [],
          data: %{
            detail: 0,
            label: "prod_0",
            name: Broadway3.Broadway.Producer_0,
            show_detail?: false
          },
          level: 0,
          max: 0.0,
          min: 0.0,
          pos: 0.0
        }
      ],
      pos: 0.0
    }
  end
end
