task_id = System.get_env("TASK", "tips")
n = String.to_integer(System.get_env("N", "8"))
out = System.get_env("OUT", ".real/code-#{task_id}-#{n}.json")

printer = fn
  %{kind: "tool", agent: a, tool: t, arg: arg} -> IO.puts("  a#{a} #{t} #{arg}")
  %{kind: "tests", agent: a, exit: e} -> IO.puts("  a#{a} run_tests → exit #{e}")
  %{kind: "finished", agent: a, outcome: o, turns: t} -> IO.puts("a#{a} finished: #{o} after #{t} turns")
  %{kind: "judged", agent: a, visible_exit: v, hidden_exit: h, p_ship: p} -> IO.puts("a#{a} judged: suite #{v} hidden #{h} Clef #{round(p * 100)}%")
  _ -> :ok
end

report = SwarmDesk.Code.Run.start(task_id, n, printer)
File.write!(out, Jason.encode!(report, pretty: true))

passed = Enum.count(report.candidates, &(&1.hidden_exit == 0))
tokens_in = report.candidates |> Enum.map(& &1.usage.in) |> Enum.sum()
tokens_out = report.candidates |> Enum.map(& &1.usage.out) |> Enum.sum()
IO.puts("\n#{task_id}: #{n} agents, #{passed}/#{n} passed hidden tests, #{Float.round(report.ms / 1000, 1)} s, tokens #{tokens_in} in / #{tokens_out} out")
IO.puts("verdict: #{report.verdict.decision} agent #{inspect(report.verdict.winner)} · #{report.verdict.reason}")
IO.puts("wrote #{out}")
