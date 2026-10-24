defmodule SwarmDesk.Web do
  use Plug.Router

  plug :match
  plug Plug.Parsers, parsers: [:json], pass: ["*/*"], json_decoder: Jason, length: 8_000_000
  plug :dispatch

  post "/ask" do
    case SwarmDesk.Ask.run(conn.body_params) do
      {:ok, result} -> conn |> put_resp_content_type("application/json") |> send_resp(200, Jason.encode!(result))
      {:error, message} -> send_resp(conn, 400, message)
    end
  end

  get "/" do
    conn |> put_resp_content_type("text/html") |> send_resp(200, File.read!(Path.join(:code.priv_dir(:swarm_desk), "index.html")))
  end

  post "/start" do
    conn = Plug.Conn.fetch_query_params(conn)
    count = conn.query_params |> Map.get("n", "200") |> Integer.parse() |> case do
      {n, _} -> n |> min(1000) |> max(1)
      :error -> 200
    end
    SwarmDesk.Mode.set_clairic(Map.get(conn.query_params, "clairic", "0") == "1")

    cond do
      not SwarmDesk.Limit.allow?(:start, 6, 60_000) -> send_resp(conn, 429, "Six runs a minute max. Try again in a moment.")
      true ->
        case SwarmDesk.Swarm.start(count) do
          :ok -> send_resp(conn, 202, "started")
          {:error, :running} -> send_resp(conn, 409, "A run is already going. Watch it, it ends in seconds.")
        end
    end
  end

  post "/try" do
    text = conn.body_params |> Map.get("text", "") |> to_string() |> String.trim() |> String.slice(0, 600)

    cond do
      text == "" -> send_resp(conn, 400, "Write a ticket first.")
      not SwarmDesk.Limit.allow?(:try, 30, 60_000) -> send_resp(conn, 429, "Too many tries this minute. Wait a moment.")
      true ->
        result = SwarmDesk.TicketAgent.handle(0, text)
        conn |> put_resp_content_type("application/json") |> send_resp(200, Jason.encode!(result))
    end
  end

  get "/code" do
    conn |> put_resp_content_type("text/html") |> send_resp(200, File.read!(Path.join(:code.priv_dir(:swarm_desk), "code.html")))
  end

  post "/code/start" do
    cond do
      not SwarmDesk.Limit.allow?(:code_start, 2, 600_000) -> send_resp(conn, 429, "Two coding runs per 10 minutes. Each run costs about $3 of model calls.")
      true ->
        case SwarmDesk.Code.Live.start() do
          :ok -> send_resp(conn, 202, "started")
          {:error, :running} -> send_resp(conn, 409, "A run is already going. Watch it, it ends in about a minute.")
        end
    end
  end

  get "/code/summary" do
    conn |> put_resp_content_type("application/json") |> send_resp(200, Jason.encode!(SwarmDesk.Code.Live.snapshot()))
  end

  get "/code/ledger" do
    conn |> put_resp_content_type("application/json") |> send_resp(200, Jason.encode!(SwarmDesk.Code.Ledger.summary()))
  end

  get "/code/events" do
    SwarmDesk.Code.Live.subscribe()
    conn = conn |> put_resp_header("cache-control", "no-cache") |> put_resp_content_type("text/event-stream") |> send_chunked(200)
    stream(conn)
  end

  get "/summary" do
    conn |> put_resp_content_type("application/json") |> send_resp(200, Jason.encode!(SwarmDesk.Swarm.snapshot()))
  end

  get "/events" do
    SwarmDesk.Swarm.subscribe()
    conn = conn |> put_resp_header("cache-control", "no-cache") |> put_resp_content_type("text/event-stream") |> send_chunked(200)
    stream(conn)
  end

  match _ do
    send_resp(conn, 404, "not found")
  end

  defp stream(conn) do
    receive do
      {:event, event} ->
        case chunk(conn, "data: #{Jason.encode!(event)}\n\n") do
          {:ok, conn} -> stream(conn)
          {:error, _} -> conn
        end
    after
      15_000 ->
        case chunk(conn, ": ping\n\n") do
          {:ok, conn} -> stream(conn)
          {:error, _} -> conn
        end
    end
  end
end

defmodule SwarmDesk.Application do
  use Application

  def start(_type, _args) do
    port = String.to_integer(System.get_env("PORT", "8820"))
    SwarmDesk.Limit.init()
    children = [SwarmDesk.Http.child_spec(), {SwarmDesk.Code.TestPool, System.schedulers_online()}, SwarmDesk.Code.Live, SwarmDesk.Swarm, {Bandit, plug: SwarmDesk.Web, port: port}]
    Supervisor.start_link(children, strategy: :one_for_one, name: SwarmDesk.Supervisor)
  end
end

defmodule SwarmDesk.Http do
  @probe_host ~c"api.cloudflare.com"

  def child_spec, do: {Finch, name: SwarmDesk.Finch, pools: %{default: [size: 50, count: 4, conn_max_idle_time: 20_000, pool_max_idle_time: 60_000, conn_opts: [transport_opts: [inet6: ipv6?(), timeout: 8_000]]]}}

  def ipv6? do
    case :persistent_term.get({__MODULE__, :ipv6}, :unknown) do
      :unknown ->
        answer = not reachable?(:inet) and reachable?(:inet6)
        :persistent_term.put({__MODULE__, :ipv6}, answer)
        answer

      known ->
        known
    end
  end

  defp reachable?(family) do
    case :gen_tcp.connect(@probe_host, 443, [family], 3_000) do
      {:ok, socket} ->
        :gen_tcp.close(socket)
        true

      _ ->
        false
    end
  end
end
