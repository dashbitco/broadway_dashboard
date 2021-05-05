defmodule BroadwayDashboard.PipelineGraphTest do
  use ExUnit.Case, async: true

  alias BroadwayDashboard.Counters
  alias BroadwayDashboard.PipelineGraph
  alias BroadwayDashboard.PipelineGraph.{Node, Layer}

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

  defp new_unique_name do
    :"Elixir.Broadway#{System.unique_integer([:positive, :monotonic])}"
  end

  describe "build_layers/2" do
    test "pipeline with batchers" do
      broadway = new_unique_name()

      Broadway.start_link(Forwarder,
        name: broadway,
        context: %{test_pid: self()},
        producer: [module: {Broadway.DummyProducer, []}],
        processors: [default: [concurrency: 10]],
        batchers: [default: [concurrency: 2], s3: [concurrency: 3]]
      )

      Counters.start!(broadway)

      topology = Broadway.topology(broadway)
      [processors | _] = topology[:processors]

      Counters.put_processing_factor(broadway, :"#{processors.name}_0", 42)

      assert %Layer{nodes: producers, children: [processors_layer]} =
               PipelineGraph.build_layers(broadway, topology)

      assert [%Node{data: %{label: "prod_0", detail: 0, show_detail?: false}}] = producers

      assert %Layer{nodes: processors, children: [default_batch_layer, s3_batch_layer]} =
               processors_layer

      assert length(processors) == 10

      [first_processor | rest_of_processors] = processors

      assert first_processor.data.detail == 42

      for {processor, idx} <- Enum.with_index(rest_of_processors, 1) do
        assert %Node{data: %{label: label, detail: 0, show_detail?: true}} = processor
        assert label == "proc_#{idx}"
      end

      assert %Layer{nodes: [default_batcher], children: default_batch_processors} =
               default_batch_layer

      assert %Node{data: %{label: "default"}} = default_batcher

      assert length(default_batch_processors) == 2

      for {processor, idx} <- Enum.with_index(default_batch_processors) do
        assert %Node{data: %{label: label, detail: 0, show_detail?: true}} = processor
        assert label == "default_#{idx}"
      end

      assert %Layer{nodes: [s3_batcher], children: s3_batch_processors} = s3_batch_layer
      assert %Node{data: %{label: "s3"}} = s3_batcher

      assert length(s3_batch_processors) == 3

      for {processor, idx} <- Enum.with_index(s3_batch_processors) do
        assert %Node{data: %{label: label, detail: 0, show_detail?: true}} = processor
        assert label == "s3_#{idx}"
      end
    end

    test "pipeline without batchers" do
      broadway = new_unique_name()

      Broadway.start_link(Forwarder,
        name: broadway,
        context: %{test_pid: self()},
        producer: [module: {Broadway.DummyProducer, []}],
        processors: [default: [concurrency: 10]]
      )

      Counters.start!(broadway)

      topology = Broadway.topology(broadway)

      assert %Layer{children: [processors_layer]} = PipelineGraph.build_layers(broadway, topology)

      assert %Layer{children: []} = processors_layer
    end

    test "calculate positions" do
      broadway = new_unique_name()

      Broadway.start_link(Forwarder,
        name: broadway,
        context: %{test_pid: self()},
        producer: [module: {Broadway.DummyProducer, []}],
        processors: [default: [concurrency: 4]],
        batchers: [default: [concurrency: 2], s3: [concurrency: 2]]
      )

      Counters.start!(broadway)

      topology = Broadway.topology(broadway)

      # It's the root and there is one node
      assert %Layer{
               pos: 1.5,
               min: -0.5,
               max: 3.5,
               level: 0,
               nodes: [producer],
               children: [processors_layer]
             } = PipelineGraph.build_layers(broadway, topology)

      assert %Node{pos: 0.0, min: 0.0, max: 0.0} = producer

      assert %Layer{
               pos: 1.5,
               level: 1,
               min: 0.0,
               max: 0.0,
               nodes: processors,
               children: [default_batch_layer, s3_batch_layer]
             } = processors_layer

      assert Enum.all?(processors, fn p -> {p.min, p.max, p.pos} == {0.0, 0.0, 0.0} end)

      assert %Layer{
               pos: 0.5,
               level: 2,
               min: 0.0,
               max: 0.0,
               nodes: [default],
               children: default_batch_processors
             } = default_batch_layer

      assert %Node{pos: 0.0, min: 0.0, max: 0.0} = default

      assert %Layer{
               pos: 2.5,
               level: 2,
               min: 0.0,
               max: 0.0,
               nodes: [s3],
               children: s3_batch_processors
             } = s3_batch_layer

      assert %Node{pos: 0.0, min: 0.0, max: 0.0} = s3

      assert [
               %Node{
                 children: [],
                 level: 3,
                 max: 0.0,
                 min: 0.0,
                 pos: 0
               },
               %Node{
                 children: [],
                 level: 3,
                 max: 0.0,
                 min: 0.0,
                 pos: 1
               }
             ] = default_batch_processors

      assert [
               %Node{
                 children: [],
                 level: 3,
                 max: 0.0,
                 min: 0.0,
                 pos: 2
               },
               %Node{
                 children: [],
                 level: 3,
                 max: 0.0,
                 min: 0.0,
                 pos: 3
               }
             ] = s3_batch_processors
    end
  end
end
