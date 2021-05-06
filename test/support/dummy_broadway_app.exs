# This file is a self contained Broadway application.
# It is used in integration tests for distribution
# testing.
Mix.install([:broadway])

defmodule MyDummy do
  use Broadway

  def start_link(_opts) do
    Broadway.start_link(__MODULE__,
      name: __MODULE__,
      producer: [
        module: {Broadway.DummyProducer, []},
        concurrency: 1
      ],
      processors: [default: [concurrency: 5]],
      batchers: [default: [concurrency: 1]]
    )
  end

  @impl true
  def handle_message(_, %Broadway.Message{} = message, _) do
    message
  end

  @impl true
  def handle_batch(:default, messages, _, _) do
    messages
  end
end

{:ok, _} = Application.ensure_all_started(:broadway)

IO.puts("starting pipeline #{inspect(MyDummy)}")

MyDummy.start_link([])
