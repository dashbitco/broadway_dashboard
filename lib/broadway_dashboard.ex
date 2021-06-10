defmodule BroadwayDashboard do
  use Phoenix.LiveDashboard.PageBuilder, refresher?: false

  @moduledoc "README.md"
             |> File.read!()
             |> String.split("<!-- MDOC !-->")
             |> Enum.fetch!(1)

  alias BroadwayDashboard.Metrics
  alias BroadwayDashboard.PipelineGraph

  # We check the Broadway version installed on remote nodes.
  # This should match mix.exs.
  @minimum_broadway_version "0.7.0-dev"

  # TODO: update link
  @disabled_link "https://hexdocs.pm/broadway_dashboard"
  @page_title "Broadway pipelines"

  @impl true
  def init(opts) do
    pipelines = Keyword.get(opts, :pipelines, [])

    {:ok, %{pipelines: pipelines}, application: :broadway}
  end

  @impl true
  def menu_link(%{pipelines: pipelines}, _capabilities) do
    case pipelines do
      [] ->
        {:disabled, @page_title, @disabled_link}

      [_ | _] ->
        {:ok, @page_title}
    end
  end

  @impl true
  def mount(params, %{pipelines: pipelines}, socket) do
    socket = assign(socket, :pipelines, pipelines)

    nav = params["nav"]
    [first_pipeline | _] = pipelines

    nav_pipeline =
      if nav && nav != "" do
        to_existing_atom_or_nil(nav)
      end

    pipeline = nav_pipeline && Enum.find(pipelines, fn name -> name == nav_pipeline end)

    cond do
      nav && is_nil(pipeline) ->
        to = live_dashboard_path(socket, socket.assigns.page, nav: first_pipeline)
        {:ok, push_redirect(socket, to: to)}

      pipeline && connected?(socket) ->
        node = socket.assigns.page.node

        with :ok <- check_broadway_version(node),
             {:ok, initial_payload} <- Metrics.listen(node, self(), pipeline) do
          stats = %{
            successful: initial_payload.successful,
            failed: initial_payload.failed,
            throughput_successful: 0,
            throughput_failed: 0
          }

          layers = PipelineGraph.build_layers(initial_payload.topology_workload)

          {:ok, assign(socket, pipeline: pipeline, stats: stats, layers: layers)}
        else
          {:error, error} ->
            {:ok, assign(socket, pipeline: nil, error: error)}
        end

      first_pipeline && is_nil(nav_pipeline) ->
        to = live_dashboard_path(socket, socket.assigns.page, nav: first_pipeline)
        {:ok, push_redirect(socket, to: to)}

      true ->
        {:ok, assign(socket, pipeline: nil, error: :pipeline_not_found)}
    end
  end

  defp to_existing_atom_or_nil(nav) do
    String.to_existing_atom(nav)
  rescue
    ArgumentError -> nil
  end

  @impl true
  def handle_info({:update_pipeline, payload}, socket) do
    if socket.assigns.pipeline == payload.pipeline do
      previous_stats = socket.assigns.stats

      stats = %{
        successful: payload.successful,
        failed: payload.failed,
        throughput_successful: payload.successful - previous_stats.successful,
        throughput_failed: payload.failed - previous_stats.failed
      }

      layers = PipelineGraph.build_layers(payload.topology_workload)

      {:noreply, assign(socket, stats: stats, layers: layers)}
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

  defp render_pipeline(%{error: _} = assigns) do
    error_message =
      case assigns.error do
        :pipeline_not_found ->
          "This pipeline is not available for this node."

        :pipeline_is_not_running ->
          "This pipeline is not running on this node."

        :version_is_not_enough ->
          "Broadway is outdated on remote node. Minimum version required is #{@minimum_broadway_version}"

        {:badrpc, _} ->
          "Could not send request to node. Try again later."
      end

    row(
      components: [
        columns(
          components: [
            card(value: error_message)
          ]
        )
      ]
    )
  end

  defp render_pipeline(assigns) do
    row(
      components: [
        columns(
          components: [
            pipeline_throughput_row(assigns.stats)
          ]
        ),
        columns(
          components: [
            pipeline_graph_row(assigns.layers)
          ]
        )
      ]
    )
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

  @hint """
  Each stage of Broadway is represented here by a circle.
  A greener circle means that the stage is most of the time "free".
  When the color change to red it means that the process is doing
  its work.
  You may want to play with the configuration of your pipeline to
  find the sweet spot between a high throughput and a lower number of
  processes in red.
  """

  defp pipeline_graph_row(layers) do
    row(
      title: "Graph",
      components: [
        columns(
          components: [
            layered_graph(
              layers: layers,
              title: "Pipeline",
              hint: @hint,
              background: &background/1,
              format_detail: &format_detail/1
            )
          ]
        )
      ]
    )
  end

  defp background(node_data) when is_binary(node_data) do
    "gray"
  end

  defp background(node_data) do
    # This calculation is defining the Hue portion of the HSL color function.
    # By definition, the value 0 is red and the value 120 is green.
    # See: https://developer.mozilla.org/en-US/docs/Web/CSS/color_value#hsl_colors
    hue = 100 - node_data.detail

    "hsl(#{hue}, 80%, 35%)"
  end

  defp format_detail(node_data) do
    "#{node_data.detail}%"
  end

  defp check_broadway_version(node) do
    case :rpc.call(node, Application, :spec, [:broadway, :vsn]) do
      {:badrpc, _reason} = error ->
        {:error, error}

      vsn when is_list(vsn) ->
        if Version.compare(to_string(vsn), @minimum_broadway_version) in [:gt, :eq] do
          :ok
        else
          {:error, :version_is_not_enough}
        end

      nil ->
        {:error, :broadway_is_not_loaded}
    end
  end
end
