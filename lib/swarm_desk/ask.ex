defmodule SwarmDesk.Ask do
  alias SwarmDesk.Models

  @max_items 1000
  @concurrency 200

  def run(%{"items" => items, "questions" => questions} = request) when is_list(items) and is_map(questions) do
    model = model_for(Map.get(request, "model", "clef"))
    started = System.monotonic_time(:millisecond)

    answers =
      items
      |> Enum.take(@max_items)
      |> Enum.with_index()
      |> Task.async_stream(fn {item, index} -> answer(model, item, questions, index) end, max_concurrency: @concurrency, timeout: 90_000, on_timeout: :kill_task)
      |> Enum.map(fn
        {:ok, row} -> row
        {:exit, reason} -> %{error: inspect(reason)}
      end)

    {:ok, %{model: model, count: length(answers), errors: Enum.count(answers, &Map.has_key?(&1, :error)), wall_ms: System.monotonic_time(:millisecond) - started, answers: answers}}
  end

  def run(_), do: {:error, "send {items: [...], questions: {...}, model?: clef|clairic}"}

  defp model_for("clairic"), do: Models.clairic()
  defp model_for(_), do: Models.clef()

  defp answer(model, item, questions, index) do
    started = System.monotonic_time(:millisecond)
    state = if is_binary(item), do: item, else: Jason.encode!(item)

    case Models.run(model, %{"state" => state, "questions" => questions}) do
      {:ok, %{"answers" => answers}} -> %{index: index, answers: answers, ms: System.monotonic_time(:millisecond) - started}
      {:ok, other} -> %{index: index, answers: other, ms: System.monotonic_time(:millisecond) - started}
      {:error, reason} -> %{index: index, error: reason, ms: System.monotonic_time(:millisecond) - started}
    end
  end
end
