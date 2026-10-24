defmodule SwarmDesk.Code.Run do
  alias SwarmDesk.Code.{Agent, Judge, Workspace}

  @benches Path.expand("../../../bench", __DIR__)

  def bench_dir, do: Path.join(@benches, System.get_env("BENCH_SUITE", "tally"))

  def task(id) do
    spec = bench_dir() |> Path.join("intents.json") |> File.read!() |> Jason.decode!()
    intent = Enum.find(spec["intents"], &(&1["id"] == id)) || raise "no task #{id}"
    %{id: id, title: intent["title"], why: intent["why"], footprint: intent["footprint"], acceptance: intent["acceptance"], conventions: File.read!(Path.join(bench_dir(), "conventions.md"))}
  end

  def catalog do
    spec = bench_dir() |> Path.join("intents.json") |> File.read!() |> Jason.decode!()
    Enum.map(spec["intents"], &%{id: &1["id"], title: &1["title"], why: &1["why"]})
  end

  def start(task_id, n, on_event \\ fn _ -> :ok end, spec \\ nil) do
    task = task(task_id)
    root = Path.join(System.tmp_dir!(), "swarm-code-#{task_id}-#{System.unique_integer([:positive])}")
    base = Workspace.prepare_base(Path.join(bench_dir(), "seed"), root)
    agents = for i <- 1..n, do: %{id: i, dir: Workspace.add_worktree(base, "agent-#{i}")}
    started = System.monotonic_time(:millisecond)
    on_event.(%{kind: "start", task: Map.take(task, [:id, :title, :why, :acceptance]), agents: Enum.map(agents, & &1.id), root: root})

    candidates =
      agents
      |> Task.async_stream(&attempt(&1, task, on_event, spec), max_concurrency: n, timeout: 900_000, on_timeout: :kill_task, ordered: false)
      |> Enum.map(fn
        {:ok, candidate} -> candidate
        {:exit, reason} -> %{agent: nil, outcome: :crashed, note: inspect(reason), visible_exit: 1, hidden_exit: 1, soft: %{p_ship: 0.0}, usage: %{in: 0, out: 0}, files: []}
      end)

    verdict = Judge.pick(candidates)
    report = %{task: task.id, n: n, ms: System.monotonic_time(:millisecond) - started, verdict: verdict, candidates: Enum.map(candidates, &Map.drop(&1, [:diff])), winner_diff: winner_diff(candidates, verdict), model: SwarmDesk.Code.LLM.model(), tests: SwarmDesk.Code.TestPool.stats(), root: root}
    on_event.(Map.put(report, :kind, "verdict"))
    report
  end

  def attempt_one(task_id, spec, on_event \\ fn _ -> :ok end) do
    task = task(task_id)
    root = Path.join(System.tmp_dir!(), "swarm-eval-#{task_id}-#{System.unique_integer([:positive])}")
    base = Workspace.prepare_base(Path.join(bench_dir(), "seed"), root)
    result = attempt(%{id: 1, dir: Workspace.add_worktree(base, "agent-1")}, task, on_event, spec)
    File.rm_rf!(root)
    Map.drop(result, [:diff])
  end

  defp attempt(agent, task, on_event, spec) do
    result = Agent.run(%{id: agent.id, dir: agent.dir, task: task, on_event: on_event, spec: spec})
    diff = Workspace.diff(agent.dir)
    files = Judge.changed(agent.dir)
    visible = if files == [], do: 1, else: Judge.visible(agent.dir)
    soft = if visible == 0, do: Judge.soft(task, diff), else: %{p_ship: 0.0, skipped: "suite failed"}
    hidden = if files == [], do: 1, else: Judge.hidden(agent.dir, task.id, Path.join(bench_dir(), "accept"))
    on_event.(%{kind: "judged", agent: agent.id, visible_exit: visible, hidden_exit: hidden, p_ship: soft.p_ship})
    Map.merge(result, %{files: files, diff_bytes: byte_size(diff), diff: diff, visible_exit: visible, hidden_exit: hidden, soft: soft})
  end

  defp winner_diff(candidates, %{winner: id}) when is_integer(id), do: candidates |> Enum.find(&(&1.agent == id)) |> Map.get(:diff)
  defp winner_diff(_, _), do: nil
end
