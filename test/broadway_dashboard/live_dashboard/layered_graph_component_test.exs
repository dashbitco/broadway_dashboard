defmodule BroadwayDashboard.LiveDashboard.LayeredGraphComponentTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest
  @endpoint Phoenix.LiveDashboardTest.Endpoint

  alias BroadwayDashboard.LiveDashboard.LayeredGraphComponent

  setup do
    # TODO: investigate why the module is not loaded automatically.
    # Possible a bug.
    Code.ensure_loaded(LayeredGraphComponent)

    :ok
  end

  describe "rendering" do
    defp circles_and_arrows_count(content) do
      fragment = Floki.parse_fragment!(content)

      {
        length(Floki.find(fragment, ".broadway-dashboard circle")),
        length(Floki.find(fragment, ".broadway-dashboard line"))
      }
    end

    defp labels(content) do
      content
      |> Floki.parse_fragment!()
      |> Floki.find(".graph-circle-label")
      |> Floki.text(sep: " | ")
    end

    test "renders a basic broadway pipeline" do
      title = "my pipeline"
      hint = "a Broadway pipeline represented as a graph"

      layers = [
        [
          %{
            id: MyPipeline.Broadway.Producer_0,
            data: %{
              label: "prod_0",
              detail: 0
            },
            children: [MyPipeline.Broadway.Processor_default_0]
          }
        ],
        [
          %{
            id: MyPipeline.Broadway.Processor_default_0,
            data: %{
              detail: 1,
              label: "proc_1"
            },
            children: []
          }
        ]
      ]

      format_detail = fn data ->
        case data.detail do
          0 -> "zero"
          1 -> "one"
          _ -> "n_n"
        end
      end

      content =
        render_component(LayeredGraphComponent,
          layers: layers,
          hint: hint,
          title: title,
          format_detail: format_detail
        )

      assert content =~ hint
      assert content =~ title

      assert content =~ "<line"
      assert content =~ "<text"

      assert content =~ "prod_0"
      assert content =~ "zero"

      assert content =~ "proc_1"
      assert content =~ "one"

      assert circles_and_arrows_count(content) == {2, 1}
    end

    test "renders correctly in case of intercalation of nodes" do
      layers = [
        [
          %{id: "a1", data: "a1", children: ["b1", "b3", "b5"]},
          %{id: "a2", data: "a2", children: ["b2", "b4", "b6"]}
        ],
        [
          %{id: "b1", data: "b1", children: []},
          %{id: "b2", data: "b2", children: []},
          %{id: "b3", data: "b3", children: []},
          %{id: "b4", data: "b4", children: []},
          %{id: "b5", data: "b5", children: []},
          %{id: "b6", data: "b6", children: []}
        ]
      ]

      content =
        render_component(LayeredGraphComponent,
          layers: layers,
          hint: "don't overlap",
          title: "a graph"
        )

      assert content =~ "a1"
      assert content =~ "b6"

      assert circles_and_arrows_count(content) == {8, 6}

      assert labels(content) == "a1 | a2 | b1 | b3 | b5 | b2 | b4 | b6"
    end

    test "show_grid? option controls the grid display" do
      layers = [
        [
          %{id: "a1", data: "a1", children: ["b1"]}
        ],
        [
          %{id: "b1", data: "b1", children: []}
        ]
      ]

      content =
        render_component(LayeredGraphComponent,
          layers: layers,
          title: "with a grid"
        )

      refute content =~ ~s[fill="url(#grid)"]

      content =
        render_component(LayeredGraphComponent,
          layers: layers,
          show_grid?: true,
          title: "with a grid"
        )

      assert content =~ ~s[fill="url(#grid)"]
    end
  end
end
