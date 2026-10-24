{:ok, _} = Application.ensure_all_started([:req, :jason])
{:ok, _} = Supervisor.start_link([SwarmDesk.Http.child_spec()], strategy: :one_for_one)
dir = Path.expand("proofs/work")
File.mkdir_p!(dir)
tries = String.to_integer(System.get_env("TRIES", "3"))
set = System.get_env("SET", "hard")
claims = if set == "hard", do: SwarmDesk.Proofs.HardClaims.all(), else: SwarmDesk.Proofs.Claims.all()
out = System.get_env("OUT", ".real/proofs-#{set}.json")

run = fn arm ->
  t0 = System.monotonic_time(:millisecond)
  rows = claims |> Task.async_stream(&SwarmDesk.Proofs.Prover.prove(arm, &1, dir, tries), max_concurrency: 30, timeout: 900_000) |> Enum.map(fn {:ok, r} -> r end)
  %{arm: arm, wall_ms: System.monotonic_time(:millisecond) - t0, proved: Enum.count(rows, & &1.proved), first_try: Enum.count(rows, &(&1.proved and &1.calls == 1)), rows: rows}
end

SwarmDesk.Opus.reset_usage()
alone = run.(:alone)
alone_usage = Map.new(SwarmDesk.Opus.usage_table())
SwarmDesk.Opus.reset_usage()
guided = run.(:guided)
guided_usage = Map.new(SwarmDesk.Opus.usage_table())

usd = fn u -> Float.round(u[:input] * 15.0 / 1_000_000 + u[:output] * 75.0 / 1_000_000, 4) end
attach = fn arm, u -> Map.put(arm, :opus, %{calls: u[:calls], input_tokens: u[:input], output_tokens: u[:output], usd_list_price: usd.(u)}) end
results = [attach.(alone, alone_usage), attach.(guided, guided_usage)]
{lean_version, _} = System.cmd("lean", ["--version"])

File.write!(out, Jason.encode!(%{set: set, claims: length(claims), tries: tries, model: "claude-opus-5-5", judge: String.trim(lean_version), price_assumption: "Opus list price $15/M in, $75/M out; OpenCode gateway billing is not visible to us", arms: results}, pretty: true))

for r <- results do
  IO.puts("#{r.arm}: proved #{r.proved}/#{length(claims)} · first try #{r.first_try} · opus calls #{r.opus.calls} · tokens #{r.opus.input_tokens} in / #{r.opus.output_tokens} out · ~$#{r.opus.usd_list_price} · wall #{r.wall_ms} ms")
end
