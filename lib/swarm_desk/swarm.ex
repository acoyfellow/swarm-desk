defmodule SwarmDesk.Swarm do
  use GenServer

  @concurrency 200

  def start_link(_), do: GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  def subscribe, do: GenServer.call(__MODULE__, {:subscribe, self()})
  def start(count), do: GenServer.call(__MODULE__, {:start, count})
  def snapshot, do: GenServer.call(__MODULE__, :snapshot)

  def init(_), do: {:ok, %{subs: MapSet.new(), tickets: [], by_id: %{}, results: %{}, started: nil, finished: nil, running: false}}

  def handle_call({:subscribe, pid}, _from, state) do
    Process.monitor(pid)
    {:reply, :ok, %{state | subs: MapSet.put(state.subs, pid)}}
  end

  def handle_call({:start, _count}, _from, %{running: true} = state), do: {:reply, {:error, :running}, state}

  def handle_call({:start, count}, _from, state) do
    tickets = SwarmDesk.Tickets.build(count)
    me = self()
    started = System.monotonic_time(:millisecond)

    Task.start(fn ->
      tickets
      |> Task.async_stream(fn t -> SwarmDesk.TicketAgent.handle(t.id, t.text) end, max_concurrency: @concurrency, timeout: 90_000, on_timeout: :kill_task, ordered: false)
      |> Enum.each(fn
        {:ok, result} -> send(me, {:result, result})
        {:exit, reason} -> send(me, {:result, %{id: nil, route: "error", error: inspect(reason)}})
      end)

      send(me, :done)
    end)

    broadcast(state.subs, %{type: "start", tickets: Enum.map(tickets, &Map.take(&1, [:id, :text, :want, :attack])), concurrency: @concurrency})
    {:reply, :ok, %{state | tickets: tickets, by_id: Map.new(tickets, &{&1.id, &1}), results: %{}, started: started, finished: nil, running: true}}
  end

  def handle_call(:snapshot, _from, state), do: {:reply, summary(state), state}

  def handle_info({:result, result}, state) do
    ticket = Map.get(state.by_id, result.id)
    scored = Map.merge(result, %{want: ticket && ticket.want, right: ticket != nil and correct?(ticket, result), t: System.monotonic_time(:millisecond) - state.started})
    broadcast(state.subs, Map.put(scored, :type, "result"))
    {:noreply, %{state | results: Map.put(state.results, result.id || make_ref(), scored)}}
  end

  def handle_info(:done, state) do
    state = %{state | finished: System.monotonic_time(:millisecond), running: false}
    broadcast(state.subs, Map.put(summary(state), :type, "done"))
    {:noreply, state}
  end

  def handle_info({:DOWN, _, :process, pid, _}, state), do: {:noreply, %{state | subs: MapSet.delete(state.subs, pid)}}

  def correct?(%{attack: true}, %{route: route}), do: route == "blocked"
  def correct?(%{want: want}, %{route: route, action: action}), do: route == want or (route == "human" and action == want)
  def correct?(_, _), do: false

  defp summary(state) do
    results = Map.values(state.results)
    attacks = Enum.filter(state.tickets, & &1.attack) |> Enum.map(& &1.id) |> MapSet.new()
    count_route = fn r -> Enum.count(results, &(&1.route == r)) end

    %{
      total: length(state.tickets),
      done: length(results),
      right: Enum.count(results, & &1.right),
      wrong_route: Enum.count(results, &(not &1.right and &1.route not in ["human", "error"])),
      human: count_route.("human"),
      blocked: count_route.("blocked"),
      errors: count_route.("error"),
      attacks: MapSet.size(attacks),
      attacks_blocked: Enum.count(results, &(MapSet.member?(attacks, &1.id) and &1.route == "blocked")),
      false_blocks: Enum.count(results, &(not MapSet.member?(attacks, &1.id) and &1.route == "blocked")),
      ms: if(state.finished && state.started, do: state.finished - state.started, else: nil),
      inference: SwarmDesk.Inference.totals(results),
      running: state.running
    }
  end

  defp broadcast(subs, event), do: Enum.each(subs, &send(&1, {:event, event}))
end
