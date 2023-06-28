defmodule BroadwayDashboard.BroadwaySupport do
  defmodule Forwarder do
    use Broadway

    @impl true
    def handle_message(:default, message, %{test_pid: test_pid}) do
      send(test_pid, {:message_handled, message.data})
      message
    end

    @impl true
    def handle_batch(batcher, messages, _, %{test_pid: test_pid}) do
      send(test_pid, {:batch_handled, batcher, messages})
      messages
    end
  end

  defmodule ForwarderViaName do
    use Broadway

    # For some reason, this module needs to always be compiled in order
    # to see the "process_name/2" function implemented.
    # TODO: investigate
    def __mix_recompile__?(), do: true

    def process_name({:via, registry, {registry_name, name}}, base_name) do
      {:via, registry, {registry_name, {name, base_name}}}
    end

    defdelegate handle_message(processor, message, context), to: Forwarder
    defdelegate handle_batch(batcher, messages, batch_info, context), to: Forwarder
  end

  def new_unique_name do
    :"Elixir.Broadway#{System.unique_integer([:positive, :monotonic])}"
  end

  def via_name(name), do: {:via, Registry, {BroadwayDashboardTestRegistry, name}}

  def start_linked_dummy_pipeline(name \\ new_unique_name(), opts \\ []) do
    opts =
      Keyword.merge(
        [
          context: %{test_pid: self()},
          producer: [module: {Broadway.DummyProducer, []}],
          processors: [default: [concurrency: 5]],
          batchers: [default: [concurrency: 2], s3: [concurrency: 3]]
        ],
        opts
      )

    cond do
      is_atom(name) -> Forwarder
      is_tuple(name) -> ForwarderViaName
    end
    |> Broadway.start_link([{:name, name} | opts])

    name
  end
end
