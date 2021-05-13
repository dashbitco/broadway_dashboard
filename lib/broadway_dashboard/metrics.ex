defmodule BroadwayDashboard.Metrics do
  @moduledoc false
  use GenServer

  alias BroadwayDashboard.Counters
  alias BroadwayDashboard.Telemetry
  alias BroadwayDashboard.Teleporter
  alias BroadwayDashboard.Listeners

  @default_interval 1_000

  # It does polling every 1 second for new metrics from
  # pipelines to pages listening for events.
  # It monitor pages and unsubscribe them in case of exit.

  def listen(target_node, parent, pipeline) do
    msg = {:listen, parent, pipeline}

    if target_node == node() do
      GenServer.call(__MODULE__, msg)
    else
      with :ok <- ensure_server_started_at_node(target_node) do
        GenServer.call({__MODULE__, target_node}, msg)
      end
    end
  end

  defp ensure_server_started_at_node(target_node) do
    case :rpc.call(target_node, Process, :whereis, [__MODULE__]) do
      pid when is_pid(pid) ->
        :ok

      nil ->
        with :ok <- Teleporter.teleport_metrics_code(target_node),
             pid when is_pid(pid) <-
               Node.spawn(target_node, __MODULE__, :start, [[from_node: node()]]) do
          :ok
        else
          _ ->
            {:error, :not_able_to_start_remotely}
        end

      {:badrpc, _} = error ->
        {:error, error}
    end
  end

  def ensure_counters_restarted(pipeline) do
    GenServer.call(__MODULE__, {:ensure_counters_restarted, pipeline})
  end

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def start(opts) do
    GenServer.start(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(opts) do
    Process.flag(:trap_exit, true)

    interval = opts[:interval] || @default_interval

    state = %{
      listeners: %{},
      refs: MapSet.new(),
      interval: interval,
      mode: opts[:refresh_mode],
      from_node: opts[:from_node]
    }

    if state.from_node do
      :net_kernel.monitor_nodes(true, node_type: :all)
    end

    {:ok, Map.put(state, :timer, maybe_schedule_refresh(state))}
  end

  defp maybe_schedule_refresh(state) do
    unless state.mode == :manual do
      Process.send_after(self(), :refresh, state.interval)
    end
  end

  @impl true
  def handle_call({:ensure_counters_restarted, pipeline}, _, state) do
    if Map.get(state.listeners, pipeline) do
      Counters.start!(pipeline)
    end

    {:reply, :ok, state}
  end

  @impl true
  def handle_call({:listen, parent, pipeline}, _, state) do
    case Process.whereis(pipeline) do
      pid when is_pid(pid) ->
        ref = Process.monitor(parent)

        listeners = Listeners.add(state.listeners, pipeline, parent)

        # This is no-op if the pipeline was started already
        Counters.start(pipeline)

        # This is no-op if the attach was already made.
        # It's important to attach only after starting the counters
        # because we need them present.
        Telemetry.attach(self())

        {:reply, :ok, %{state | refs: MapSet.put(state.refs, ref), listeners: listeners}}

      nil ->
        {:reply, {:error, :pipeline_not_found}, state}
    end
  end

  @impl true
  def handle_info(:refresh, state) do
    Enum.map(state.listeners, fn {pipeline, listeners} ->
      Enum.map(listeners, fn pid ->
        send(pid, {:refresh_stats, pipeline})
      end)
    end)

    {:noreply, %{state | timer: maybe_schedule_refresh(state)}}
  end

  @impl true
  def handle_info({:DOWN, ref, _, pid, _}, %{refs: refs} = state) do
    listeners = Listeners.remove(state.listeners, pid)

    {:noreply, %{state | refs: MapSet.delete(refs, ref), listeners: listeners}}
  end

  @impl true
  def handle_info({:nodedown, from_node, _}, %{from_node: from_node} = state) do
    {:stop, :normal, state}
  end

  @impl true
  def handle_info(_, state) do
    {:noreply, state}
  end

  @impl true
  def terminate(_reason, state) do
    if state.timer, do: Process.cancel_timer(state.timer)

    Telemetry.detach(self())

    state.listeners
    |> Map.keys()
    |> Enum.map(fn pipeline -> Counters.erase(pipeline) end)

    :ok
  end
end
