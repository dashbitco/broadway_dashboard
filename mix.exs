defmodule BroadwayDashboard.MixProject do
  use Mix.Project

  def project do
    [
      app: :broadway_dashboard,
      version: "0.1.0",
      elixir: "~> 1.11",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger],
      mod: {BroadwayDashboard.Application, []}
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:phoenix_live_dashboard, github: "phoenixframework/phoenix_live_dashboard"},
      {:broadway, github: "dashbitco/broadway"},
      {:jason, "~> 1.0", only: [:dev, :test, :docs]},
      {:floki, "~> 0.27.0", only: :test}
    ]
  end
end
