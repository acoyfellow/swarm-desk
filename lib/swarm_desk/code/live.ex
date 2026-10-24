defmodule SwarmDesk.Code.Live do
  use GenServer
  alias SwarmDesk.Code.Run

  @usd_in 3 / 1_000_000
  @usd_out 15 / 1_000_000

  def start_link(_), do: GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  def subscribe, do: GenServer.call(__MODULE__, {:subscribe, self()})
  def start, do: GenServer.call(__MODULE__, :start)
  def snapshot, do: GenServer.call(__MODULE__, :snapshot)

  def init(_) do
    catalog = Run.catalog()
    {:ok, %{subs: MapSet.new(), running: false, order: Enum.map(catalog, & &1.id), tasks: fresh(catalog), started: nil, ms: nil}}
  end

  def handle_call({:subscribe, pid}, _from, state) do
    Process.monitor(pid)
    {:reply, :ok, %{state | subs: MapSet.put(state.subs, pid)}}
  end

  def handle_call(:start, _from, %{running: true} = state), do: {:reply, {:error, :running}, state}

  def handle_call(:start, _from, state) do
    me = self()
    ids = state.order

    Task.start(fn ->
      ids
      |> Task.async_stream(&run_one(&1, me), max_concurrency: length(ids), timeout: 900_000, on_timeout: :kill_task, ordered: false)
      |> Stream.run()

      send(me, :done)
    end)

    state = %{state | running: true, tasks: fresh(Run.catalog()), started: System.monotonic_time(:millisecond), ms: nil}
    broadcast(state.subs, %{type: "start", tasks: ordered(state)})
    {:reply, :ok, state}
  end

  def handle_call(:snapshot, _from, state), do: {:reply, view(state), state}

  def handle_info({:ev, id, event}, state) do
    case Map.fetch(state.tasks, id) do
      {:ok, task} ->
        updated = apply_event(task, event)
        broadcast(state.subs, %{type: "task", kind: event[:kind], task: updated, elapsed: elapsed(state)})
        {:noreply, %{state | tasks: Map.put(state.tasks, id, updated)}}

      :error ->
        {:noreply, state}
    end
  end

  def handle_info(:done, state) do
    state = %{state | running: false, ms: elapsed(state)}
    record(view(state))
    broadcast(state.subs, view(state) |> Map.put(:type, "done") |> Map.put(:ledger, SwarmDesk.Code.Ledger.summary()))
    {:noreply, state}
  end

  def handle_info({:DOWN, _, :process, pid, _}, state), do: {:noreply, %{state | subs: MapSet.delete(state.subs, pid)}}

  defp record(%{summary: s, ms: ms}) do
    SwarmDesk.Code.Ledger.record(%{
      "at" => DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601(),
      "agents" => s.total,
      "shipped" => s.shipped,
      "person" => s.person,
      "hidden_pass" => s.hidden_pass,
      "wrong_ships" => s.wrong_ships,
      "tokens_in" => s.tokens_in,
      "tokens_out" => s.tokens_out,
      "usd" => s.usd,
      "seconds" => Float.round(ms / 1000, 1),
      "model" => SwarmDesk.Code.LLM.model()
    })
  end

  defp run_one(id, me) do
    Run.start(id, 1, &send(me, {:ev, id, &1}))
  rescue
    error -> send(me, {:ev, id, %{kind: "crashed", error: Exception.message(error)}})
  end

  defp apply_event(task, %{kind: "tool"} = e), do: %{task | status: "working", tool: e.tool, arg: e.arg, turns: e.turn}
  defp apply_event(task, %{kind: "tests"} = e), do: %{task | tests: task.tests + 1, last_test_exit: e.exit}
  defp apply_event(task, %{kind: "finished"} = e), do: %{task | status: "judging", outcome: to_string(e.outcome), turns: e.turns, tokens_in: e.usage.in, tokens_out: e.usage.out, agent_ms: e.ms}
  defp apply_event(task, %{kind: "judged"} = e), do: %{task | visible: e.visible_exit == 0, hidden: e.hidden_exit == 0, p_ship: e.p_ship}

  defp apply_event(task, %{kind: "verdict"} = e) do
    files = e.candidates |> List.first(%{}) |> Map.get(:files, [])
    %{task | status: "done", decision: e.verdict.decision, reason: e.verdict.reason, diff: e.winner_diff || first_diff(e), files: files, ms: e.ms}
  end

  defp apply_event(task, %{kind: "crashed"} = e), do: %{task | status: "done", decision: "person", reason: "agent crashed: #{e.error}"}
  defp apply_event(task, _), do: task

  defp first_diff(%{candidates: [%{diff_bytes: 0} | _]}), do: nil
  defp first_diff(_), do: nil

  defp fresh(catalog) do
    Map.new(catalog, fn t ->
      {t.id, %{id: t.id, title: t.title, why: t.why, status: "idle", tool: nil, arg: nil, turns: 0, tests: 0, last_test_exit: nil, outcome: nil, visible: nil, hidden: nil, p_ship: nil, decision: nil, reason: nil, files: [], diff: nil, tokens_in: 0, tokens_out: 0, agent_ms: nil, ms: nil}}
    end)
  end

  defp ordered(state), do: Enum.map(state.order, &Map.fetch!(state.tasks, &1))

  defp view(state) do
    tasks = ordered(state)
    done = Enum.filter(tasks, &(&1.status == "done"))
    shipped = Enum.filter(done, &(&1.decision == "ship"))
    tokens_in = tasks |> Enum.map(& &1.tokens_in) |> Enum.sum()
    tokens_out = tasks |> Enum.map(& &1.tokens_out) |> Enum.sum()

    %{
      running: state.running,
      elapsed: elapsed(state),
      ms: state.ms,
      tasks: tasks,
      summary: %{
        total: length(tasks),
        done: length(done),
        shipped: length(shipped),
        person: Enum.count(done, &(&1.decision == "person")),
        hidden_pass: Enum.count(done, &(&1.hidden == true)),
        wrong_ships: Enum.count(shipped, &(&1.hidden != true)),
        tokens_in: tokens_in,
        tokens_out: tokens_out,
        usd: Float.round(tokens_in * @usd_in + tokens_out * @usd_out, 2)
      }
    }
  end

  defp elapsed(%{started: nil}), do: 0
  defp elapsed(%{ms: ms}) when is_integer(ms), do: ms
  defp elapsed(state), do: System.monotonic_time(:millisecond) - state.started

  defp broadcast(subs, event), do: Enum.each(subs, &send(&1, {:event, event}))
end
