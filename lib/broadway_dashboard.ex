defmodule BroadwayDashboard do
  use Phoenix.LiveDashboard.PageBuilder, refresher?: false

  @moduledoc "README.md"
             |> File.read!()
             |> String.split("<!-- MDOC !-->")
             |> Enum.fetch!(1)

  alias BroadwayDashboard.{Metrics, PipelineGraph}

  # We check the Broadway version installed on remote nodes.
  # This should match mix.exs.
  @minimum_broadway_version "1.0.0"

  @disabled_link "https://hexdocs.pm/broadway_dashboard"
  @page_title "Broadway pipelines"

  @impl true
  def init(opts) do
    pipelines = opts[:pipelines] || :auto_discover

    {:ok, %{pipelines: pipelines}, application: :broadway}
  end

  @impl true
  def menu_link(%{pipelines: pipelines}, _capabilities) do
    if pipelines == [] do
      {:disabled, @page_title, @disabled_link}
    else
      {:ok, @page_title}
    end
  end

  defp pipelines_or_auto_discover(pipeline_config, node) do
    cond do
      pipeline_config == [] ->
        {:error, :no_pipelines_available}

      is_list(pipeline_config) ->
        {:ok, pipeline_config}

      pipeline_config == :auto_discover ->
        with :ok <- check_broadway_version(node) do
          running_pipelines(node)
        end

      true ->
        {:error, :no_pipelines_available}
    end
  end

  defp running_pipelines(node) do
    case :rpc.call(node, Broadway, :all_running, []) do
      [] ->
        {:error, :no_pipelines_available}

      pipelines when is_list(pipelines) ->
        {:ok, pipelines}

      {:badrpc, _error} ->
        {:error, :cannot_list_running_pipelines}
    end
  end

  @impl true
  def mount(params, %{pipelines: pipelines}, socket) do
    case pipelines_or_auto_discover(pipelines, socket.assigns.page.node) do
      {:ok, pipelines} ->
        socket = assign(socket, :pipelines, pipelines)
        pipeline = nav_pipeline(params, pipelines)

        cond do
          pipeline ->
            node = socket.assigns.page.node

            with :ok <- check_socket_connection(socket),
                 :ok <- check_broadway_version(node),
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

          true ->
            nav = pipelines |> hd() |> inspect()
            to = live_dashboard_path(socket, socket.assigns.page, nav: nav)
            {:ok, push_redirect(socket, to: to)}
        end

      {:error, error} ->
        {:ok, assign(socket, pipeline: nil, error: error)}
    end
  end

  defp nav_pipeline(params, pipelines) do
    nav = params["nav"]
    nav = if nav && nav != "", do: nav
    nav && Enum.find(pipelines, fn name -> inspect(name) == nav end)
  end

  defp check_socket_connection(socket) do
    if connected?(socket) do
      :ok
    else
      {:error, :connection_is_not_available}
    end
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
  def render(assigns) do
    if assigns[:error] do
      render_error(assigns)
    else
      items =
        for name <- assigns.pipelines do
          name = inspect(name)

          {name,
           name: name, render: fn -> render_pipeline_or_error(assigns) end, method: :redirect}
        end

      nav_bar(items: items, page: assigns[:page])
    end
  end

  defp nav_bar(opts) do
    assigns = Map.new(opts)

    ~H"""
    <.live_nav_bar id="broadway_navbar" page={@page}>
      <:item name={name} :for={{name, item} <- @items}>
        <%= item[:render].() %>
      </:item>
    </.live_nav_bar>
    """
  end

  defp render_pipeline_or_error(assigns) do
    if assigns[:error] do
      render_error(assigns)
    else
      render_pipeline(assigns)
    end
  end

  defp render_pipeline(assigns) do
    ~H"""
    <.row>
      <:col>
        <.pipeline_throughput_row stats={@stats} />
        <.pipeline_graph_row layers={@layers} />
      </:col>
    </.row>
    """
  end

  defp render_error(assigns) do
    error_message = error_message(assigns)
    assigns = Map.put(assigns, :error_message, error_message)

    ~H"""
    <.row>
      <:col>
        <.card><%= @error_message %></.card>
      </:col>
    </.row>
    """
  end

  defp error_message(assigns) do
    case assigns.error do
      :connection_is_not_available ->
        "Dashboard is not connected yet."

      :pipeline_not_found ->
        "This pipeline is not available for this node."

      :pipeline_is_not_running ->
        "This pipeline is not running on this node."

      :broadway_is_not_available ->
        "Broadway is not available on remote node."

      :version_is_not_enough ->
        "Broadway is outdated on remote node. Minimum version required is #{@minimum_broadway_version}"

      :no_pipelines_available ->
        "There is no pipeline running on this node."

      :cannot_list_running_pipelines ->
        "Could not list running pipelines at remote node. Please try again later."

      :not_able_to_start_remotely ->
        "Could not start the metrics server remotely. Please try again later."

      {:badrpc, _} ->
        "Could not send request to node. Try again later."
    end
  end

  defp pipeline_throughput_row(assigns) do
    ~H"""
    <.row>
      <:col>
        <.row>
          <:col>
            <.card title="Throughput" hint="Messages p/ second." inner_title="successful"><%= @stats.throughput_successful %></.card>
          </:col>
          <:col>
            <.card inner_title="failed"><%= @stats.throughput_failed %></.card>
          </:col>
          <:col>
            <.card inner_title="total"><%= @stats.throughput_successful + @stats.throughput_failed %></.card>
          </:col>
        </.row>
      </:col>
      <:col>
        <.row>
          <:col>
            <.card title="All time" hint="Messages since start." inner_title="successful"><%= @stats.successful %></.card>
          </:col>
          <:col>
            <.card inner_title="failed"><%= @stats.failed %></.card>
          </:col>
          <:col>
            <.card inner_title="total"><%= @stats.successful + @stats.failed %></.card>
          </:col>
        </.row>
      </:col>
    </.row>
    """
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

  defp pipeline_graph_row(assigns) do
    assigns = Map.put(assigns, :hint, @hint)

    ~H"""
    <.row>
      <:col>
        <.live_layered_graph layers={@layers} id="pipeline" title="Pipeline" hint={@hint} background={&background/1} format_detail={&format_detail/1} />
      </:col>
    </.row>
    """
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
        {:error, :broadway_is_not_available}
    end
  end
end
