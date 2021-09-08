defmodule BroadwayDashboard.PipelineGraphTest do
  use ExUnit.Case, async: true

  alias BroadwayDashboard.{Counters, PipelineGraph, BroadwaySupport}
  import BroadwayDashboard.BroadwaySupport

  describe "build_layers/2" do
    test "without batchers" do
      broadway = BroadwaySupport.new_unique_name()

      start_linked_dummy_pipeline(
        broadway,
        processors: [default: [concurrency: 3]],
        batchers: []
      )

      topology = Broadway.topology(broadway)
      counters = Counters.build(topology)

      topology_workload = Counters.topology_workload(counters, topology)

      assert [
               [%{id: _prod_id, children: [_proc1, _proc2, _proc3], data: "prod_0"}],
               [
                 %{id: _proc_0, children: [], data: %{label: "proc_0", detail: 0}},
                 %{id: _proc_1, children: [], data: %{label: "proc_1", detail: 0}},
                 %{id: _proc_2, children: [], data: %{label: "proc_2", detail: 0}}
               ]
             ] = PipelineGraph.build_layers(topology_workload)
    end

    test "with batchers" do
      broadway = BroadwaySupport.new_unique_name()

      start_linked_dummy_pipeline(
        broadway,
        processors: [default: [concurrency: 3]],
        batchers: [default: [concurrency: 2], s3: [concurrency: 1]]
      )

      topology = Broadway.topology(broadway)
      counters = Counters.build(topology)

      topology_workload = Counters.topology_workload(counters, topology)

      assert [
               [%{id: prod_id, children: [proc_0, proc_1, proc_2], data: "prod_0"}],
               [
                 %{
                   id: proc_0,
                   children: [default_batcher, s3_batcher],
                   data: %{label: "proc_0", detail: 0}
                 },
                 %{
                   id: proc_1,
                   children: [default_batcher, s3_batcher],
                   data: %{label: "proc_1", detail: 0}
                 },
                 %{
                   id: proc_2,
                   children: [default_batcher, s3_batcher],
                   data: %{label: "proc_2", detail: 0}
                 }
               ],
               [
                 %{
                   children: [batch_proc_0, batch_proc_1],
                   data: %{detail: 0, label: "default"},
                   id: default_batcher
                 },
                 %{
                   children: [batch_proc_s3],
                   data: %{detail: 0, label: "s3"},
                   id: s3_batcher
                 }
               ],
               [
                 %{children: [], data: %{detail: 0, label: "proc_0"}, id: batch_proc_0},
                 %{children: [], data: %{detail: 0, label: "proc_1"}, id: batch_proc_1},
                 %{children: [], data: %{detail: 0, label: "proc_0"}, id: batch_proc_s3}
               ]
             ] = PipelineGraph.build_layers(topology_workload)

      broadway_str = inspect(broadway)

      assert prod_id == "#{broadway_str}.Broadway.Producer_0"

      assert proc_0 == "#{broadway_str}.Broadway.Processor_default_0"
      assert proc_1 == "#{broadway_str}.Broadway.Processor_default_1"
      assert proc_2 == "#{broadway_str}.Broadway.Processor_default_2"

      assert default_batcher == "#{broadway_str}.Broadway.Batcher_default"

      assert batch_proc_0 == "#{broadway_str}.Broadway.BatchProcessor_default_0"
      assert batch_proc_1 == "#{broadway_str}.Broadway.BatchProcessor_default_1"

      assert batch_proc_s3 == "#{broadway_str}.Broadway.BatchProcessor_s3_0"
    end
  end
end
