defmodule BroadwayDashboard do
  use Phoenix.LiveDashboard.PageBuilder, refresher?: false

  # TODO: add docs
  @moduledoc false

  alias BroadwayDashboard.Counters
  alias BroadwayDashboard.Metrics
  alias BroadwayDashboard.PipelineGraph
  alias BroadwayDashboard.LiveDashboard.PipelineComponent

  # TODO: update link
  @disabled_link "https://hexdocs.pm/broadway_dashboard"

  @page_title "Broadway pipelines"

  @impl true
  def init(opts) do
    pipelines = Keyword.get(opts, :pipelines, [])

    {:ok, %{pipelines: pipelines}, application: :broadway}
  end

  @impl true
  def menu_link(%{pipelines: []}, _capabilities) do
    if Code.ensure_loaded?(Broadway) do
      {:disabled, @page_title, @disabled_link}
    else
      :skip
    end
  end

  # TODO: handle case when there is no process in _capabilities
  # with our pipeline name
  @impl true
  def menu_link(%{pipelines: _}, _capabilities) do
    {:ok, @page_title}
  end

  @impl true
  def mount(params, %{pipelines: pipelines}, socket) do
    nav = params["nav"]
    [first_pipeline | _] = pipelines

    nav_pipeline =
      if nav && nav != "" do
        to_existing_atom_or_nil(nav)
      else
        first_pipeline
      end

    pipeline = Enum.find(pipelines, fn name -> name == nav_pipeline end)

    socket = assign(socket, :pipelines, pipelines)

    cond do
      nav_pipeline && is_nil(pipeline) ->
        to = live_dashboard_path(socket, socket.assigns.page, nav: first_pipeline)
        {:ok, push_redirect(socket, to: to)}

      pipeline && connected?(socket) ->
        node = socket.assigns.page.node

        :ok = Metrics.listen(node, self(), pipeline)

        {successful, failed} = Counters.count(node, pipeline)

        stats = %{
          successful: successful,
          failed: failed,
          throughput_successful: 0,
          throughput_failed: 0
        }

        {:ok, assign(socket, pipeline: pipeline, stats: stats)}

      first_pipeline && is_nil(nav_pipeline) ->
        to = live_dashboard_path(socket, socket.assigns.page, nav: first_pipeline)
        {:ok, push_redirect(socket, to: to)}

      true ->
        {:ok, assign(socket, pipeline: nil)}
    end
  end

  defp to_existing_atom_or_nil(nav) do
    try do
      String.to_existing_atom(nav)
    rescue
      ArgumentError ->
        nil
    end
  end

  @impl true
  def handle_info({:refresh_stats, pipeline}, socket) do
    if pipeline == socket.assigns.pipeline do
      node = socket.assigns.page.node

      previous_stats = socket.assigns.stats
      {successful, failed} = Counters.count(node, pipeline)

      stats = %{
        successful: successful,
        failed: failed,
        throughput_successful: successful - previous_stats.successful,
        throughput_failed: failed - previous_stats.failed
      }

      {:noreply, assign(socket, :stats, stats)}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def render_page(assigns) do
    items =
      for name <- assigns.pipelines do
        {name, name: format_nav_name(name), render: render_pipeline(assigns), method: :redirect}
      end

    nav_bar(items: items)
  end

  defp format_nav_name(pipeline_name) do
    "Elixir." <> name = Atom.to_string(pipeline_name)

    name
  end

  defp render_pipeline(assigns) do
    if assigns.pipeline do
      row(
        components: [
          columns(
            components: [
              pipeline_throughput_row(assigns.stats)
            ]
          ),
          columns(components: [pipeline_graph_row(assigns.page.node, assigns.pipeline)])
        ]
      )
    else
      row(
        components: [
          columns(
            components: [
              card(value: "This pipeline is not available for this node.")
            ]
          )
        ]
      )
    end
  end

  defp pipeline_throughput_row(stats) do
    row(
      components: [
        columns(
          components: [
            row(
              components: [
                columns(
                  components: [
                    card(
                      title: "Throughput",
                      hint: "Messages p/ second.",
                      inner_title: "successful",
                      value: stats.throughput_successful
                    ),
                    card(inner_title: "failed", value: stats.throughput_failed),
                    card(
                      inner_title: "total",
                      value: stats.throughput_successful + stats.throughput_failed
                    )
                  ]
                )
              ]
            ),
            row(
              components: [
                columns(
                  components: [
                    card(
                      title: "All time",
                      hint: "Messages since start.",
                      inner_title: "successful",
                      value: stats.successful
                    ),
                    card(inner_title: "failed", value: stats.failed),
                    card(inner_title: "total", value: stats.successful + stats.failed)
                  ]
                )
              ]
            )
          ]
        )
      ]
    )
  end

  defp pipeline_graph_row(node, pipeline) do
    graph = PipelineGraph.build_layers(node, pipeline)

    hint = """
    Each stage of Broadway is represented here by a circle.
    A greener circle means that the stage is most of the time "free".
    When the color change to red it means that the process is doing
    its work.
    You may want to play with the configuration of your pipeline to
    find the sweet spot between a high throughput and a lower number of
    processes in red.
    """

    row(
      title: "Graph",
      components: [
        columns(
          components: [
            {PipelineComponent, [graph: graph, title: "Pipeline", hint: hint]}
          ]
        )
      ]
    )
  end
end
