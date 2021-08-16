Application.put_env(:phoenix_live_dashboard, Phoenix.LiveDashboardTest.Endpoint,
  url: [host: "localhost", port: 4002],
  secret_key_base: "Hu4qQN3iKzTV4fJxhorPQlA/osH9fAMtbtjVS58PFgfw3ja5Z18Q/WSNR9wP4OfW",
  live_view: [signing_salt: "hMegieSe"],
  render_errors: [view: Phoenix.LiveDashboardTest.ErrorView],
  check_origin: false,
  pubsub_server: Phoenix.LiveDashboardTest.PubSub
)

defmodule Demo.Pipeline do
  use Broadway

  def start_link(opts) do
    Broadway.start_link(__MODULE__,
      name: opts[:broadway_name] || __MODULE__,
      producer: [
        module: {Broadway.DummyProducer, opts},
        concurrency: 1
      ],
      processors: [
        default: [concurrency: 10]
      ],
      batchers: [
        default: [batch_size: 20, concurrency: 4, batch_timeout: 2000],
        s3: [concurrency: 3, batch_size: 15, batch_timeout: 2000]
      ]
    )
  end

  @impl true
  def handle_message(_, %Broadway.Message{} = message, _) do
    Broadway.Message.update_data(message, fn data ->
      String.upcase(data)
    end)
    |> Broadway.Message.put_batcher(pick_batcher_key())
  end

  @impl true
  def handle_batch(:default, messages, _, _) do
    Enum.map(messages, fn message ->
      Broadway.Message.update_data(message, fn data ->
        String.downcase(data)
      end)
    end)
  end

  @impl true
  def handle_batch(:s3, messages, _, _), do: messages

  defp pick_batcher_key do
    Enum.random([:default, :s3])
  end
end

defmodule UsesRegistry do
  use Broadway

  def handle_message(_, message, _), do: message
  def handle_batch(_, messages, _, _), do: messages

  def process_name({:via, Registry, {registry, id}}, base_name) do
    {:via, Registry, {registry, {id, base_name}}}
  end
end

defmodule Phoenix.LiveDashboardTest.ErrorView do
  use Phoenix.View, root: "test/templates"

  def template_not_found(template, _assigns) do
    Phoenix.Controller.status_message_from_template(template)
  end
end

defmodule Phoenix.LiveDashboardTest.Telemetry do
  import Telemetry.Metrics

  def metrics do
    [
      counter("phx.b.c"),
      counter("phx.b.d"),
      counter("ecto.f.g"),
      counter("my_app.h.i")
    ]
  end
end

defmodule Phoenix.LiveDashboardTest.Router do
  use Phoenix.Router
  import Phoenix.LiveDashboard.Router

  pipeline :browser do
    plug(:fetch_session)
  end

  scope "/", ThisWontBeUsed, as: :this_wont_be_used do
    pipe_through(:browser)

    live_dashboard("/dashboard",
      metrics: Phoenix.LiveDashboardTest.Telemetry,
      additional_pages: [
        broadway: {BroadwayDashboard, pipelines: [Demo.Pipeline, MyDummy, MyDummyOutdated]},
        broadway_auto_discovery: BroadwayDashboard
      ]
    )
  end
end

defmodule Phoenix.LiveDashboardTest.Endpoint do
  use Phoenix.Endpoint, otp_app: :phoenix_live_dashboard

  plug(Phoenix.LiveDashboard.RequestLogger,
    param_key: "request_logger_param_key",
    cookie_key: "request_logger_cookie_key"
  )

  plug(Plug.Session,
    store: :cookie,
    key: "_live_view_key",
    signing_salt: "/VEDsdfsffMnp5"
  )

  plug(Phoenix.LiveDashboardTest.Router)
end

{:ok, _} =
  Supervisor.start_link(
    [
      {Phoenix.PubSub, name: Phoenix.LiveDashboardTest.PubSub, adapter: Phoenix.PubSub.PG2},
      Phoenix.LiveDashboardTest.Endpoint
    ],
    strategy: :one_for_one
  )

exclude = if Node.alive?(), do: [], else: [distribution: true]

ExUnit.start(exclude: exclude)
