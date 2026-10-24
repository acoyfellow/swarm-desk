n = String.to_integer(System.get_env("N", "8"))
parallel_tasks = String.to_integer(System.get_env("TASKS_AT_ONCE", "4"))
only = System.get_env("ONLY", "")
out = System.get_env("OUT", "bench/results.json")

ids =
  "bench/tally/intents.json" |> File.read!() |> Jason.decode!() |> Map.fetch!("intents") |> Enum.map(& &1["id"])
  |> then(fn all -> if only == "", do: all, else: Enum.filter(all, &(&1 in String.split(only, ","))) end)

IO.puts("#{length(ids)} tasks × #{n} agents, #{parallel_tasks} tasks at once, model #{SwarmDesk.Code.LLM.model()}")
started = System.monotonic_time(:millisecond)

rows =
  ids
  |> Task.async_stream(
    fn id ->
      report = SwarmDesk.Code.Run.start(id, n)
      attempts = report.candidates
      winner = Enum.find(attempts, &(&1.agent == report.verdict.winner))
      row = %{
        task: id,
        attempts: length(attempts),
        visible_pass: Enum.count(attempts, &(&1.visible_exit == 0)),
        hidden_pass: Enum.count(attempts, &(&1.hidden_exit == 0)),
        single_agent_rate: Enum.count(attempts, &(&1.hidden_exit == 0)) / max(length(attempts), 1),
        decision: report.verdict.decision,
        winner: report.verdict.winner,
        winner_p_ship: winner && winner.soft.p_ship,
        winner_hidden_pass: winner != nil and winner.hidden_exit == 0,
        any_hidden_pass: Enum.any?(attempts, &(&1.hidden_exit == 0)),
        tokens_in: attempts |> Enum.map(& &1.usage.in) |> Enum.sum(),
        tokens_out: attempts |> Enum.map(& &1.usage.out) |> Enum.sum(),
        ms: report.ms,
        attempts_detail: Enum.map(attempts, &%{agent: &1.agent, outcome: &1.outcome, turns: &1[:turns], visible: &1.visible_exit, hidden: &1.hidden_exit, p_ship: &1.soft.p_ship})
      }
      IO.puts("#{String.pad_trailing(id, 18)} hidden #{row.hidden_pass}/#{n} · visible #{row.visible_pass}/#{n} · #{row.decision} a#{inspect(row.winner)} → hidden #{if row.winner_hidden_pass, do: "PASS", else: "fail"} · #{Float.round(report.ms / 1000, 1)} s")
      row
    end,
    max_concurrency: parallel_tasks,
    timeout: 1_800_000,
    ordered: false
  )
  |> Enum.map(fn {:ok, row} -> row end)
  |> Enum.sort_by(& &1.task)

count = length(rows)
single = rows |> Enum.map(& &1.single_agent_rate) |> Enum.sum()
picked_pass = Enum.count(rows, & &1.winner_hidden_pass)
shipped = Enum.filter(rows, &(&1.decision == "ship"))
summary = %{
  tasks: count,
  agents_per_task: n,
  model: SwarmDesk.Code.LLM.model(),
  one_agent_expected_pass: Float.round(single, 2),
  swarm_pick_pass: picked_pass,
  oracle_any_pass: Enum.count(rows, & &1.any_hidden_pass),
  shipped: length(shipped),
  shipped_and_right: Enum.count(shipped, & &1.winner_hidden_pass),
  shipped_and_wrong: Enum.count(shipped, &(not &1.winner_hidden_pass)),
  held_for_person: count - length(shipped),
  held_but_right: Enum.count(rows, &(&1.decision == "person" and &1.winner_hidden_pass)),
  tokens_in: rows |> Enum.map(& &1.tokens_in) |> Enum.sum(),
  tokens_out: rows |> Enum.map(& &1.tokens_out) |> Enum.sum(),
  wall_s: Float.round((System.monotonic_time(:millisecond) - started) / 1000, 1)
}
summary = Map.put(summary, :usd_list_price, Float.round(summary.tokens_in * 3 / 1_000_000 + summary.tokens_out * 15 / 1_000_000, 2))
File.write!(out, Jason.encode!(%{summary: summary, rows: rows}, pretty: true))
IO.puts("\n" <> Jason.encode!(summary, pretty: true))
