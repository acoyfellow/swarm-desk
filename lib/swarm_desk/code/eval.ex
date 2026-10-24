defmodule SwarmDesk.Code.Eval do
  alias SwarmDesk.Code.Run

  def load_spec(path), do: path |> File.read!() |> Jason.decode!()

  def run(spec_paths, opts) do
    specs = Enum.map(spec_paths, &load_spec/1)
    tasks = Keyword.get(opts, :tasks) || Enum.map(Run.catalog(), & &1.id)
    repeats = Keyword.get(opts, :repeats, 1)
    on_row = Keyword.get(opts, :on_row, fn _ -> :ok end)
    concurrency = Keyword.get(opts, :concurrency, 64)
    cells = for spec <- specs, task <- tasks, r <- 1..repeats, do: {spec, task, r}
    started = System.monotonic_time(:millisecond)

    rows =
      cells
      |> Task.async_stream(fn {spec, task, r} -> cell(spec, task, r, on_row) end, max_concurrency: concurrency, timeout: 1_200_000, on_timeout: :kill_task, ordered: false)
      |> Enum.zip(cells)
      |> Enum.map(fn
        {{:ok, row}, _} -> row
        {{:exit, reason}, {spec, task, r}} -> %{spec: spec["name"], task: task, repeat: r, outcome: "crashed", note: inspect(reason) |> String.slice(0, 200), visible: false, hidden: false, p_ship: 0.0, ship: false, turns: 0, tests_run: 0, tokens_in: 0, tokens_out: 0, usd: 0.0, ms: 0}
      end)

    %{
      specs: specs,
      tasks: tasks,
      repeats: repeats,
      cells: length(cells),
      wall_ms: System.monotonic_time(:millisecond) - started,
      by_spec: Enum.map(specs, &score(&1, rows)),
      rows: Enum.sort_by(rows, &{&1.spec, &1.task, &1.repeat})
    }
  end

  defp cell(spec, task, repeat, on_row) do
    result = Run.attempt_one(task, spec)
    price = spec["price_per_m"] || %{"in" => 0, "out" => 0}
    usd = result.usage.in * price["in"] / 1_000_000 + result.usage.out * price["out"] / 1_000_000

    row = %{
      spec: spec["name"],
      task: task,
      repeat: repeat,
      outcome: to_string(result.outcome),
      turns: result.turns,
      tests_run: result.tests_run,
      visible: result.visible_exit == 0,
      hidden: result.hidden_exit == 0,
      p_ship: result.soft.p_ship,
      ship: result.visible_exit == 0 and result.soft.p_ship >= SwarmDesk.Code.Judge.ship_at(),
      tokens_in: result.usage.in,
      tokens_out: result.usage.out,
      usd: Float.round(usd, 4),
      ms: result.ms
    }

    on_row.(row)
    row
  end

  defp score(spec, rows) do
    mine = Enum.filter(rows, &(&1.spec == spec["name"]))
    n = max(length(mine), 1)
    shipped = Enum.filter(mine, & &1.ship)
    ms = mine |> Enum.map(& &1.ms) |> Enum.sort()

    %{
      spec: spec["name"],
      model: spec["model"],
      tools: spec["tools"],
      cells: length(mine),
      hidden_pass: Enum.count(mine, & &1.hidden),
      hidden_pass_rate: Float.round(Enum.count(mine, & &1.hidden) / n, 3),
      shipped: length(shipped),
      shipped_wrong: Enum.count(shipped, &(not &1.hidden)),
      held_right: Enum.count(mine, &(not &1.ship and &1.hidden)),
      crashed_or_model_error: Enum.count(mine, &(&1.outcome in ["crashed", "model_error"])),
      usd: mine |> Enum.map(& &1.usd) |> Enum.sum() |> Float.round(2),
      usd_per_pass: if(Enum.count(mine, & &1.hidden) > 0, do: Float.round(Enum.sum(Enum.map(mine, & &1.usd)) / Enum.count(mine, & &1.hidden), 3), else: nil),
      mean_turns: Float.round(Enum.sum(Enum.map(mine, & &1.turns)) / n, 1),
      p50_s: Float.round(Enum.at(ms, div(length(ms), 2), 0) / 1000, 1),
      max_s: Float.round((List.last(ms) || 0) / 1000, 1)
    }
  end
end
