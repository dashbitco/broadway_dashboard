defmodule BroadwayDashboard.TeleporterTest do
  use ExUnit.Case, async: false

  setup do
    hostname = current_hostname!()

    {port, name} = spawn_support_project!("dummy_broadway_app.exs")
    :ok = wait_to_start(port)

    os_pid = Port.info(port)[:os_pid]

    System.at_exit(fn _ ->
      {"", 0} = System.cmd("kill", [to_string(os_pid)])
    end)

    [node_name: :"#{name}@#{hostname}"]
  end

  @tag :distribution
  test "teleport_metrics_code/1 to a running node", %{node_name: node_name} do
    assert :ok = BroadwayDashboard.Teleporter.teleport_metrics_code(node_name)
  end

  @tag :distribution
  test "teleport_metrics_code/1 to a node that is down" do
    host = current_hostname!()

    assert {:error, {:badrpc, _reason}} =
             BroadwayDashboard.Teleporter.teleport_metrics_code(:"foo@#{host}")
  end

  defp current_hostname! do
    unless Node.alive?() do
      raise "for running distribution tests you must start with a node name and cookie"
    end

    [_, hostname] = Node.self() |> Atom.to_string() |> String.split("@")
    hostname
  end

  defp spawn_support_project!(project_file) do
    elixir_path = System.find_executable("elixir")
    cookie = Node.get_cookie()
    node_name = Base.encode16(:crypto.strong_rand_bytes(3), case: :lower)
    script_path = Path.join([__DIR__, "..", "support", project_file])

    unless File.exists?(script_path) do
      raise ArgumentError, "project file does not exist!"
    end

    args = String.split("--sname #{node_name} --no-halt --cookie #{cookie} #{script_path}")

    {Port.open({:spawn_executable, elixir_path}, [:binary, args: args]), node_name}
  end

  defp wait_to_start(port) do
    receive do
      {^port, {:data, "starting pipeline" <> _}} ->
        :ok

      _ ->
        wait_to_start(port)
    end
  end
end
