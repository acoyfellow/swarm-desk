defmodule SwarmDesk.Code.LLM do
  def model, do: System.get_env("CODE_MODEL", "claude-sonnet-5")

  def chat(system, messages, tools, max_tokens \\ 4000, model \\ nil) do
    body = %{model: model || model(), max_tokens: max_tokens, system: system, messages: messages, tools: tools}
    headers = SwarmDesk.Anthropic.headers()
    opts = [finch: [name: SwarmDesk.Finch, pool_timeout: 60_000], json: body, headers: headers, receive_timeout: 180_000, retry: :transient, max_retries: 4, retry_delay: fn n -> 1_000 * Integer.pow(2, n) + :rand.uniform(1_000) end]

    case Req.post(SwarmDesk.Anthropic.url(), opts) do
      {:ok, %{status: 200, body: %{"content" => content} = reply}} -> {:ok, %{content: content, stop: reply["stop_reason"], usage: reply["usage"] || %{}}}
      {:ok, %{status: status, body: reply}} -> {:error, "model #{status}: #{inspect(reply) |> String.slice(0, 200)}"}
      {:error, reason} -> {:error, "model: #{inspect(reason) |> String.slice(0, 200)}"}
    end
  end
end
