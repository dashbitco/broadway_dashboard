defmodule BroadwayDashboard.Metrics do
  @moduledoc false
  use GenServer

  alias BroadwayDashboard.Counters
  alias BroadwayDashboard.Telemetry
  alias BroadwayDashboard.Teleporter

  @default_interval 1_000

  # It does polling every 1 second for new metrics from
  # pipelines to pages listening for events.
  # It monitor pages and unsubscribe them in case of exit.

  def listen(target_node, parent, pipeline) do
    msg = {:listen, parent}
    name = server_name(pipeline)

    with {:ok, server_name} <- ensure_server_started_at_node(pipeline, name, target_node) do
      GenServer.call(server_name, msg)
    end
  end

  def server_name(pipeline) do
    :"BroadwayDashboard.Metrics.#{pipeline}"
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

    state = %{
      pipeline: pipeline,
      listeners: MapSet.new(),
      refs: MapSet.new(),
      interval: interval,
      mode: opts[:refresh_mode]
    }

    # TODO: get counters ref and pass to telemetry
    Counters.start(pipeline)

    # This is no-op if the attach was already made.
    # It's important to attach only after starting the counters
    Telemetry.attach(self(), pipeline)

    {:ok, Map.put(state, :timer, maybe_schedule_refresh(state))}
  end

  defp maybe_schedule_refresh(state) do
    unless state.mode == :manual do
      Process.send_after(self(), :refresh, state.interval)
    end
  end

  @impl true
  def handle_call(:ensure_counters_restarted, _, state) do
    Counters.start!(state.pipeline)

    {:reply, :ok, state}
  end

  @impl true
  def handle_call({:listen, parent}, _, state) do
    case Process.whereis(state.pipeline) do
      pid when is_pid(pid) ->
        ref = Process.monitor(parent)
        refs = MapSet.put(state.refs, ref)

        listeners = MapSet.put(state.listeners, parent)

        {:reply, :ok, %{state | refs: refs, listeners: listeners}}

      nil ->
        {:reply, {:error, :pipeline_not_found}, state}
    end
  end

  @impl true
  def handle_info(:refresh, state) do
    for pid <- state.listeners, do: send(pid, {:refresh_stats, state.pipeline})

    {:noreply, %{state | timer: maybe_schedule_refresh(state)}}
  end

  @impl true
  def handle_info({:DOWN, ref, _, pid, _}, state) do
    listeners = MapSet.delete(state.listeners, pid)
    refs = MapSet.delete(state.refs, ref)

    # TODO: check if listeners is empty and schedule shutdown after 5 if so

    {:noreply, %{state | refs: refs, listeners: listeners}}
  end

  @impl true
  def handle_info(_, state) do
    {:noreply, state}
  end

  @impl true
  def terminate(_reason, state) do
    if state.timer, do: Process.cancel_timer(state.timer)

    Telemetry.detach(self())

    Counters.erase(state.pipeline)

    :ok
  end
end
