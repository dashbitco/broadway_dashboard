defmodule BroadwayDashboard.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @mix_env Mix.env()

  @impl true
  def start(_type, _args) do
    children = [
      {BroadwayDashboard.Metrics, metrics_opts(@mix_env)}
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: BroadwayDashboard.Supervisor]
    Supervisor.start_link(children, opts)
  end

  @dialyzer {:nowarn_function, metrics_opts: 1}
  defp metrics_opts(current_env) do
    if current_env == :test do
      [refresh_mode: :manual]
    else
      []
    end
  end
end
