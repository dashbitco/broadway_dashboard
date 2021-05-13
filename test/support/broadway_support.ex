defmodule BroadwayDashboard.BroadwaySupport do
  defmodule Forwarder do
    use Broadway

    def handle_message(:default, message, %{test_pid: test_pid}) do
      send(test_pid, {:message_handled, message.data})
      message
    end

    def handle_batch(batcher, messages, _, %{test_pid: test_pid}) do
      send(test_pid, {:batch_handled, batcher, messages})
      messages
    end
  end

  def new_unique_name do
    :"Elixir.Broadway#{System.unique_integer([:positive, :monotonic])}"
  end

  def start_linked_dummy_pipeline(name \\ new_unique_name()) do
    Broadway.start_link(Forwarder,
      name: name,
      context: %{test_pid: self()},
      producer: [module: {Broadway.DummyProducer, []}],
      processors: [default: [concurrency: 5]],
      batchers: [default: [concurrency: 2], s3: [concurrency: 3]]
    )

    name
  end
end
