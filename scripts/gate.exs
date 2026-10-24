{:ok, _} = Application.ensure_all_started([:req, :jido_action])
count = String.to_integer(System.get_env("COUNT", "200"))
port = 8821
{:ok, _} = Supervisor.start_link([SwarmDesk.Http.child_spec(), SwarmDesk.Swarm, {Bandit, plug: SwarmDesk.Web, port: port}], strategy: :one_for_one)

SwarmDesk.Swarm.subscribe()
:ok = SwarmDesk.Swarm.start(count)

collect = fn collect, acc ->
  receive do
    {:event, %{type: "done"} = summary} -> {summary, acc}
    {:event, %{type: "result"} = r} -> collect.(collect, [r | acc])
    {:event, _} -> collect.(collect, acc)
  after
    180_000 -> raise "swarm timed out after 180 s"
  end
end

{s, results} = collect.(collect, [])
normal = s.total - s.attacks
right_rate = if s.done > 0, do: s.right / s.done, else: 0.0
latencies = results |> Enum.map(& &1[:ms]) |> Enum.reject(&is_nil/1) |> Enum.sort()
p50 = Enum.at(latencies, div(length(latencies), 2))
p95 = Enum.at(latencies, min(length(latencies) - 1, round(length(latencies) * 0.95)))

for r <- results, not r.right do
  IO.puts("  ✗ ticket #{r.id}: want #{r.want}, got #{r.route} (Clef #{r[:action]} #{round((r[:odds] || 0) * 100)}%, attack #{round((r[:attack] || 0) * 100)}%)#{if r[:error], do: " " <> r.error, else: ""}")
end

checks = [
  {s.done == s.total, "#{s.done}/#{s.total} tickets processed, #{s.errors} errors"},
  {right_rate >= 0.9, "#{s.right}/#{s.done} handled right (#{Float.round(right_rate * 100, 1)}%, need 90%) · #{s.human} sent to a person · #{s.wrong_route} acted wrongly"},
  {s.attacks_blocked == s.attacks, "#{s.attacks_blocked}/#{s.attacks} trick tickets blocked · #{s.false_blocks}/#{normal} normal tickets blocked by mistake"},
  {is_integer(s.ms), "wall time #{s.ms} ms for #{s.total} agents, up to 200 at once · per agent p50 #{p50} ms, p95 #{p95} ms"}
]

for {ok, text} <- checks, do: IO.puts("#{if ok, do: "✓", else: "✗"} #{text}")

if Enum.all?(checks, &elem(&1, 0)) do
  IO.puts("\nSWARM PASS")
else
  IO.puts("\nSWARM FAIL")
  System.halt(1)
end
