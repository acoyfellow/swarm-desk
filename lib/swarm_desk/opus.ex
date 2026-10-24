defmodule SwarmDesk.Opus do
  def model, do: System.get_env("OPUS_MODEL", "claude-opus-5-5")

  def ask(system, user, max_tokens \\ 1500) do
    body = %{model: model(), max_tokens: max_tokens, system: system, messages: [%{role: "user", content: user}]}
    headers = SwarmDesk.Anthropic.headers()

    case Req.post(SwarmDesk.Anthropic.url(), finch: [name: SwarmDesk.Finch, pool_timeout: 60_000], json: body, headers: headers, receive_timeout: 120_000, retry: :transient, max_retries: 2) do
      {:ok, %{status: 200, body: %{"content" => content} = body}} ->
        record_usage(body["usage"] || %{})
        {:ok, content |> Enum.filter(&(&1["type"] == "text")) |> Enum.map_join("", & &1["text"])}

      {:ok, %{status: status, body: body}} ->
        {:error, "opus #{status}: #{inspect(body) |> String.slice(0, 160)}"}

      {:error, reason} ->
        {:error, "opus: #{inspect(reason)}"}
    end
  end

  def usage_table, do: :ets.whereis(:opus_usage) != :undefined && :ets.tab2list(:opus_usage)

  def reset_usage do
    if :ets.whereis(:opus_usage) == :undefined, do: :ets.new(:opus_usage, [:named_table, :public, :set])
    :ets.insert(:opus_usage, [{:calls, 0}, {:input, 0}, {:output, 0}])
  end

  defp record_usage(usage) do
    if :ets.whereis(:opus_usage) != :undefined do
      :ets.update_counter(:opus_usage, :calls, 1)
      :ets.update_counter(:opus_usage, :input, usage["input_tokens"] || 0)
      :ets.update_counter(:opus_usage, :output, usage["output_tokens"] || 0)
    end
  end
end
