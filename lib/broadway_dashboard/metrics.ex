defmodule BroadwayDashboard.Metrics do
  @moduledoc false
  use GenServer

  alias BroadwayDashboard.NewCounters
  alias BroadwayDashboard.NewTelemetry
  alias BroadwayDashboard.Teleporter

  @default_interval 1_000

  # It does polling every 1 second for new metrics from
  # pipelines to pages listening for events.
  # It monitor pages and unsubscribe them in case of exit.

  def listen(target_node, parent, pipeline) do
    name = server_name(pipeline)

    with :ok <- check_pipeline_running_at_node(pipeline, target_node),
         {:ok, server_name} <- ensure_server_started_at_node(pipeline, name, target_node) do
      GenServer.call(server_name, {:listen, parent})
    end
  end

  def server_name(pipeline) do
    :"BroadwayDashboard.Metrics.#{pipeline}"
  end

  defp check_pipeline_running_at_node(pipeline, target_node) do
    result =
      if target_node == node() do
        Process.whereis(pipeline)
      else
        :rpc.call(target_node, Process, :whereis, [pipeline])
      end

    case result do
      pid when is_pid(pid) ->
        :ok

      _ ->
        {:error, :pipeline_not_found}
    end
  end

  defp ensure_server_started_at_node(pipeline, name, target_node) when target_node == node() do
    if Process.whereis(name) do
      {:ok, name}
    else
      with {:ok, _} <- start(pipeline: pipeline, name: name) do
        {:ok, name}
      end
    end
  end

  defp ensure_server_started_at_node(pipeline, name, target_node) do
    case :rpc.call(target_node, Process, :whereis, [name]) do
      pid when is_pid(pid) ->
        {:ok, {name, target_node}}

      nil ->
        with :ok <- Teleporter.teleport_metrics_code(target_node),
             pid when is_pid(pid) <-
               :rpc.call(target_node, __MODULE__, :start, [
                 [pipeline: pipeline, name: name]
               ]) do
          {:ok, {name, target_node}}
        else
          _ ->
            {:error, :not_able_to_start_remotely}
        end

      {:badrpc, _} = error ->
        {:error, error}
    end
  end

  def ensure_counters_restarted(pipeline) do
    name = server_name(pipeline)

    GenServer.call(name, :ensure_counters_restarted)
  end

  def start(opts) do
    GenServer.start(__MODULE__, opts, name: Keyword.fetch!(opts, :name))
  end

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: Keyword.fetch!(opts, :name))
  end

  @impl true
  def init(opts) do
    Process.flag(:trap_exit, true)

    interval = opts[:interval] || @default_interval
    pipeline = opts[:pipeline]

    topology = Broadway.topology(pipeline)
    counters = NewCounters.build(topology)

    state = %{
      pipeline: pipeline,
      listeners: Map.new(),
      interval: interval,
      counters: counters,
      shutdown_timer: nil,
      mode: opts[:refresh_mode] || :auto
    }

    NewTelemetry.attach(self(), pipeline, counters)

    {:ok, Map.put(state, :timer, maybe_schedule_refresh(state))}
  end

  defp maybe_schedule_refresh(state) do
    unless state.mode == :manual do
      Process.send_after(self(), :refresh, state.interval)
    end
  end

  @impl true
  def handle_call(:ensure_counters_restarted, _, state) do
    topology = Broadway.topology(state.pipeline)
    counters = NewCounters.build(topology)

    NewTelemetry.detach(self())
    NewTelemetry.attach(self(), state.pipeline, counters)

    {:reply, :ok, %{state | counters: counters}}
  end

  @impl true
  def handle_call({:listen, parent}, _, state) do
    ref = Process.monitor(parent)

    listeners = Map.put(state.listeners, ref, parent)

    if state.shutdown_timer, do: Process.cancel_timer(state.shutdown_timer)

    {:reply, {:ok, build_update_payload(state)},
     %{state | listeners: listeners, shutdown_timer: nil}}
  end

  @impl true
  def handle_info(:refresh, state) do
    payload = build_update_payload(state)

    for pid <- Map.values(state.listeners),
        do: send(pid, {:update_pipeline, payload})

    {:noreply, %{state | timer: maybe_schedule_refresh(state)}}
  end

  @impl true
  def handle_info({:DOWN, ref, _, _pid, _}, state) do
    listeners = Map.delete(state.listeners, ref)

    shutdown_timer =
      if listeners == %{} do
        maybe_schedule_shutdown(state)
      end

    {:noreply, %{state | listeners: listeners, shutdown_timer: shutdown_timer}}
  end

  @impl true
  def handle_info(:shutdown, state) do
    {:stop, :normal, state}
  end

  @impl true
  def handle_info(_, state) do
    {:noreply, state}
  end

  @impl true
  def terminate(_reason, _state) do
    NewTelemetry.detach(self())

    :ok
  end

  defp build_update_payload(state) do
    topology = Broadway.topology(state.pipeline)

    topology_workload = NewCounters.topology_workload(state.counters, topology)
    {:ok, {successful, failed}} = NewCounters.count(state.counters)

    %{
      pipeline: state.pipeline,
      topology_workload: topology_workload,
      successful: successful,
      failed: failed
    }
  end

  defp maybe_schedule_shutdown(state) do
    unless state.mode == :manual or state.shutdown_timer do
      Process.send_after(self(), :shutdown, state.interval * 5)
    end
  end
end
