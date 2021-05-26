defmodule BroadwayDashboard.MixProject do
  use Mix.Project

  @version "0.1.0"

  def project do
    [
      app: :broadway_dashboard,
      version: @version,
      elixir: "~> 1.11",
      start_permanent: Mix.env() == :prod,
      elixirc_paths: elixirc_paths(Mix.env()),
      aliases: aliases(),
      docs: docs(),
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
      {:phoenix_live_reload, "~> 1.2", only: :dev},
      {:plug_cowboy, "~> 2.0", only: :dev},
      {:jason, "~> 1.0", only: [:dev, :test, :docs]},
      {:ex_doc, "~> 0.24.2", only: [:dev, :docs], runtime: false},
      {:floki, "~> 0.27.0", only: :test}
    ]
  end

  defp docs do
    [
      main: "BroadwayDashboard",
      source_ref: "v#{@version}",
      source_url: "https://github.com/dashbitco/broadway_dashboard"
    ]
  end

  defp aliases do
    [dev: "run --no-halt dev.exs"]
  end

  # Specifies which paths to compile per environment.
  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]
end
