# BroadwayDashboard

A work in progress dashboard for Broadway.

## Installation

If [available in Hex](https://hex.pm/docs/publish), the package can be installed
by adding `broadway_dashboard` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:broadway_dashboard, "~> 0.1.0"}
  ]
end
```

## Integration with Phoenix Live Dashboard

You can add this page to your Live Dashboard just by adding as a page in
the `live_dashboard` macro at your router file.

```elixir
live_dashboard "/dashboard",
  additional_pages: [
    broadway: {BroadwayDashboard, pipelines: [MyBroadway]}
  ]

```

Documentation can be generated with [ExDoc](https://github.com/elixir-lang/ex_doc)
and published on [HexDocs](https://hexdocs.pm). Once published, the docs can
be found at [https://hexdocs.pm/broadway_dashboard](https://hexdocs.pm/broadway_dashboard).

