defmodule BroadwayDashboard.MixProject do
  use Mix.Project

  @version "0.4.1"
  @description "A Phoenix LiveDashboard page for inspecting your Broadway pipelines"

  def project do
    [
      app: :broadway_dashboard,
      version: @version,
      elixir: "~> 1.13",
      start_permanent: Mix.env() == :prod,
      elixirc_paths: elixirc_paths(Mix.env()),
      name: "BroadwayDashboard",
      description: @description,
      package: package(),
      aliases: aliases(),
      docs: docs(),
      deps: deps()
    ]
  end

  def application do
    [
      extra_applications: [:logger],
      mod: {BroadwayDashboard.Application, []}
    ]
  end

  defp deps do
    [
      {:broadway, "~> 1.0"},
      {:phoenix_live_dashboard, "~> 0.8.0"},
      {:phoenix_live_reload, "~> 1.2", only: :dev},
      {:phoenix_view, "~> 2.0 or ~> 1.0", only: [:test]},
      {:plug_cowboy, "~> 2.0", only: :dev},
      {:jason, "~> 1.0", only: [:dev, :test, :docs]},
      {:ex_doc, "~> 0.24", only: [:docs], runtime: false},
      {:stream_data, "~> 0.5", only: [:dev, :test]},
      {:floki, "~> 0.34", only: :test}
    ]
  end

  defp docs do
    [
      main: "BroadwayDashboard",
      source_ref: "v#{@version}",
      source_url: "https://github.com/dashbitco/broadway_dashboard",
      homepage_url: "https://elixir-broadway.org"
    ]
  end

  defp package do
    %{
      maintainers: ["Philip Sampaio"],
      licenses: ["Apache-2.0"],
      links: %{
        "GitHub" => "https://github.com/dashbitco/broadway_dashboard",
        "Broadway website" => "https://elixir-broadway.org"
      },
      files: ~w(lib CHANGELOG.md LICENSE mix.exs README.md)
    }
  end

  defp aliases do
    [dev: "run --no-halt dev.exs"]
  end

  # Specifies which paths to compile per environment.
  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]
end
