defmodule SwarmDesk.Limit do
  @table __MODULE__

  def init, do: :ets.new(@table, [:named_table, :public, write_concurrency: true])

  def allow?(bucket, max, window_ms) do
    now = System.monotonic_time(:millisecond)
    window = div(now, window_ms)
    count = :ets.update_counter(@table, {bucket, window}, 1, {{bucket, window}, 0})
    count <= max
  end
end
