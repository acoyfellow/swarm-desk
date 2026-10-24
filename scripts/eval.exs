specs = System.get_env("SPECS", "evals/agents/sonnet5-full.json") |> String.split(",")
repeats = String.to_integer(System.get_env("REPEATS", "1"))
tasks = case System.get_env("TASKS", "") do
  "" -> nil
  list -> String.split(list, ",")
end
concurrency = String.to_integer(System.get_env("CONCURRENCY", "64"))
out = System.get_env("OUT", "evals/results/latest.json")

IO.puts("eval: #{length(specs)} specs × #{if tasks, do: length(tasks), else: 16} tasks × #{repeats} repeats, #{concurrency} at once")
report = SwarmDesk.Code.Eval.run(specs, tasks: tasks, repeats: repeats, concurrency: concurrency, on_row: fn r -> IO.puts("  #{String.pad_trailing(r.spec, 15)} #{String.pad_trailing(r.task, 17)} r#{r.repeat} #{r.outcome} hidden=#{r.hidden} ship=#{r.ship} #{r.turns}t $#{r.usd}") end)
File.mkdir_p!(Path.dirname(out))
File.write!(out, Jason.encode!(report, pretty: true))
IO.puts("\nwall #{Float.round(report.wall_ms / 1000, 1)} s · #{report.cells} cells")
for s <- report.by_spec, do: IO.puts(Jason.encode!(s))
IO.puts("wrote #{out}")
