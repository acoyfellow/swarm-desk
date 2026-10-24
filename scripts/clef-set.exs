out = "bench/clef-set.json"

rows =
  SwarmDesk.Code.Run.catalog()
  |> Task.async_stream(
    fn %{id: id} ->
      report = SwarmDesk.Code.Run.start(id, 1)
      [c] = report.candidates
      diff = report.winner_diff || ""
      %{task: id, diff: diff, visible_exit: c.visible_exit, hidden_exit: c.hidden_exit, files: c.files}
    end,
    max_concurrency: 16,
    timeout: 900_000
  )
  |> Enum.map(fn {:ok, row} -> row end)

File.write!(out, Jason.encode!(rows, pretty: true))
IO.puts("#{length(rows)} diffs, #{Enum.count(rows, &(&1.hidden_exit == 0))} pass hidden, #{Enum.count(rows, &(&1.diff == ""))} empty → #{out}")
