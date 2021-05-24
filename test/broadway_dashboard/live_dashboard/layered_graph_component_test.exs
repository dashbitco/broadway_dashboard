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

  defp circles_and_arrows_count(content) do
    fragment = Floki.parse_fragment!(content)

    {
      length(Floki.find(fragment, ".broadway-dashboard circle")),
      length(Floki.find(fragment, ".broadway-dashboard line"))
    }
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
end
