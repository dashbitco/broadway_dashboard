defmodule BroadwayDashboard.Metrics do
  @moduledoc false
  use GenServer

  alias BroadwayDashboard.Counters
  alias BroadwayDashboard.Telemetry

  # It does polling every 1 second for new metrics from
  # pipelines to pages listening for events.
  # It monitor pages and unsubscribe them in case of exit.

  def listen(node, parent, pipeline) do
    :rpc.call(node, __MODULE__, :listen_callback, [parent, pipeline])
  end

  def listen_callback(parent, pipeline) do
    GenServer.call(__MODULE__, {:listen, parent, pipeline})
  end

  def ensure_counters_restarted(pipeline) do
    GenServer.cast(__MODULE__, {:ensure_counters_restarted, pipeline})
  end

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    Process.flag(:trap_exit, true)

    timer = Process.send_after(self(), :refresh, 1_000)

    {:ok, %{listeners: %{}, refs: MapSet.new(), timer: timer}}
  end

  @impl true
  def handle_cast({:ensure_counters_restarted, pipeline}, state) do
    if Map.get(state.listeners, pipeline) do
      Counters.start!(pipeline)
    end

    {:noreply, state}
  end

  @impl true
  def handle_call({:listen, parent, pipeline}, _, state) do
    ref = Process.monitor(parent)

    pipeline_listeners =
      state.listeners
      |> Map.get(pipeline, MapSet.new())
      |> MapSet.put(parent)

    listeners = Map.put(state.listeners, pipeline, pipeline_listeners)

    # This is no-op if the pipeline was started already
    Counters.start(pipeline)

    # This is no-op if the attach was already made.
    # It's important to attach only after starting the counters
    # because we need them present.
    Telemetry.attach(self())

    {:reply, :ok, %{state | refs: MapSet.put(state.refs, ref), listeners: listeners}}
  end

  @impl true
  def handle_info(:refresh, state) do
    Enum.each(state.listeners, fn {pipeline, listeners} ->
      Enum.each(listeners, fn pid ->
        send(pid, {:refresh_stats, pipeline})
      end)
    end)

    timer = Process.send_after(self(), :refresh, 1_000)

    {:noreply, %{state | timer: timer}}
  end

  @impl true
  def handle_info({:DOWN, ref, _, pid, _}, %{refs: refs} = state) do
    listeners =
      state.listeners
      |> Enum.map(fn {pipeline, pids_set} ->
        pids_set =
          if MapSet.member?(pids_set, pid) do
            MapSet.delete(pids_set, pid)
          else
            pids_set
          end

        {pipeline, pids_set}
      end)
      |> Map.new()

    {:noreply, %{state | refs: MapSet.delete(refs, ref), listeners: listeners}}
  end

  @impl true
  def terminate(_reason, state) do
    Process.cancel_timer(state.timer)
    Telemetry.detach(self())

    :ok
  end
end
