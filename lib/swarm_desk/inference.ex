defmodule SwarmDesk.Inference do
  @usd_per_million_input %{clairic: 0.10, clef: 0.24}

  def totals(results) do
    by_model =
      for model <- [:clairic, :clef], into: %{} do
        usages = for %{usage: usage} <- results, u = usage[model], is_map(u), do: u
        input = Enum.sum(Enum.map(usages, &(&1["input_tokens"] || 0)))
        output = Enum.sum(Enum.map(usages, &(&1["output_tokens"] || 0)))
        {model, %{calls: length(usages), input_tokens: input, output_tokens: output, usd: Float.round(input * @usd_per_million_input[model] / 1_000_000, 6)}}
      end

    errors = for %{route: "error", error: e} <- results, do: e |> to_string() |> String.slice(0, 120) |> String.replace(~r/\d+ ms/, "")

    %{
      models: by_model,
      usd: Float.round(by_model.clairic.usd + by_model.clef.usd, 6),
      price_source: "Workers AI model catalog: clairic $0.10, clef $0.24 per M input tokens; output not billed",
      error_kinds: errors |> Enum.frequencies() |> Enum.sort_by(fn {_, n} -> -n end) |> Enum.take(5) |> Map.new()
    }
  end
end
