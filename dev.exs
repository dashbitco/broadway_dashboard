# iex -S mix dev
Logger.configure(level: :debug)

# Configures the endpoint
Application.put_env(:phoenix_live_dashboard, DemoWeb.Endpoint,
  url: [host: "localhost"],
  secret_key_base: "Hu4qQN3iKzTV4fJxhorPQlA/osH9fAMtbtjVS58PFgfw3ja5Z18Q/WSNR9wP4OfW",
  live_view: [signing_salt: "hMegieSe"],
  http: [port: System.get_env("PORT") || 4000],
  debug_errors: true,
  check_origin: false,
  pubsub_server: Demo.PubSub
)

defmodule Demo.Pipeline do
  use Broadway

  def start_link(opts) do
    Broadway.start_link(__MODULE__,
      name: __MODULE__,
      producer: [
        module: {Broadway.DummyProducer, opts},
        concurrency: 1
      ],
      processors: [
        default: [concurrency: 10]
      ],
      batchers: [
        default: [batch_size: 20, concurrency: 3, batch_timeout: 2000],
        s3: [concurrency: 3, batch_size: 15, batch_timeout: 2000],
        s4: [concurrency: 3, batch_size: 15, batch_timeout: 2000]
      ]
    )
  end

  @impl true
  def handle_message(_, %Broadway.Message{} = message, _) do
    Broadway.Message.update_data(message, fn data ->
      hex = Base.encode16(:crypto.strong_rand_bytes(64))

      String.upcase(data <> hex)
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

defmodule FakeProducer do
  use GenServer

  def start_link(_) do
    GenServer.start_link(__MODULE__, name: __MODULE__)
  end

  def init(_) do
    timer = Process.send_after(self(), :publish, 1000)

    {:ok, timer}
  end

  def handle_info(:publish, _timer) do
    for i <- 1..1234, do: Broadway.test_message(Demo.Pipeline, "hello #{i}")

    timer = Process.send_after(self(), :publish, 100)

    {:noreply, timer}
  end

  def handle_info(_, timer) do
    {:noreply, timer}
  end

  def terminate(_, timer) do
    Process.cancel_timer(timer)

    :ok
  end
end

defmodule DemoWeb.PageController do
  import Plug.Conn

  def init(opts), do: opts

  def call(conn, :index) do
    content(conn, """
    <h2>BroadwayDashboard Dev</h2>
    <a href="/dashboard" target="_blank">Open Dashboard</a>
    """)
  end

  def call(conn, :hello) do
    name = Map.get(conn.params, "name", "friend")
    content(conn, "<p>Hello, #{name}!</p>")
  end

  defp content(conn, content) do
    conn
    |> put_resp_header("content-type", "text/html")
    |> send_resp(200, "<!doctype html><html><body>#{content}</body></html>")
  end
end

defmodule DemoWeb.Router do
  use Phoenix.Router
  import Phoenix.LiveDashboard.Router

  pipeline :browser do
    plug :fetch_session
  end

  scope "/" do
    pipe_through :browser
    get "/", DemoWeb.PageController, :index

    live_dashboard("/dashboard",
      allow_destructive_actions: true,
      additional_pages: [
        broadway: {BroadwayDashboard, pipelines: [Demo.Pipeline, BikeSharing]}
      ]
    )
  end
end

defmodule DemoWeb.Endpoint do
  use Phoenix.Endpoint, otp_app: :phoenix_live_dashboard

  socket "/live", Phoenix.LiveView.Socket
  socket "/phoenix/live_reload/socket", Phoenix.LiveReloader.Socket

  plug Phoenix.LiveReloader
  plug Phoenix.CodeReloader

  plug Phoenix.LiveDashboard.RequestLogger,
    param_key: "request_logger",
    cookie_key: "request_logger"

  plug Plug.Session,
    store: :cookie,
    key: "_live_view_key",
    signing_salt: "/VEDsdfsffMnp5"

  plug Plug.RequestId
  plug DemoWeb.Router
end

Application.ensure_all_started(:os_mon)
Application.put_env(:phoenix, :serve_endpoints, true)

Task.start(fn ->
  children = [
    {Phoenix.PubSub, [name: Demo.PubSub, adapter: Phoenix.PubSub.PG2]},
    Demo.Pipeline,
    FakeProducer,
    DemoWeb.Endpoint
  ]

  {:ok, _} = Supervisor.start_link(children, strategy: :one_for_one)

  Process.sleep(:infinity)
end)
