defmodule SwarmDesk.Code.TestPool do
  use GenServer

  def start_link(slots), do: GenServer.start_link(__MODULE__, slots, name: __MODULE__)

  def run(dir, args, timeout_ms \\ 30_000) do
    :ok = GenServer.call(__MODULE__, :acquire, :infinity)

    try do
      started = System.monotonic_time(:millisecond)
      task = Task.async(fn -> System.cmd("node", args, cd: dir, stderr_to_stdout: true, env: [{"NODE_NO_WARNINGS", "1"}]) end)

      case Task.yield(task, timeout_ms) || Task.shutdown(task, :brutal_kill) do
        {:ok, {out, code}} -> %{exit: code, output: out, ms: System.monotonic_time(:millisecond) - started}
        nil -> %{exit: 124, output: "test run timed out after #{timeout_ms} ms", ms: timeout_ms}
      end
    after
      GenServer.cast(__MODULE__, :release)
    end
  end

  def stats, do: GenServer.call(__MODULE__, :stats)

  def init(slots), do: {:ok, %{free: slots, slots: slots, waiting: :queue.new(), peak_busy: 0, runs: 0}}

  def handle_call(:acquire, from, %{free: 0} = state), do: {:noreply, %{state | waiting: :queue.in(from, state.waiting)}}

  def handle_call(:acquire, _from, state) do
    busy = state.slots - state.free + 1
    {:reply, :ok, %{state | free: state.free - 1, runs: state.runs + 1, peak_busy: max(state.peak_busy, busy)}}
  end

  def handle_call(:stats, _from, state), do: {:reply, Map.take(state, [:slots, :peak_busy, :runs]), state}

  def handle_cast(:release, state) do
    case :queue.out(state.waiting) do
      {{:value, next}, rest} ->
        GenServer.reply(next, :ok)
        {:noreply, %{state | waiting: rest, runs: state.runs + 1, peak_busy: max(state.peak_busy, state.slots)}}

      {:empty, _} ->
        {:noreply, %{state | free: state.free + 1}}
    end
  end
end
