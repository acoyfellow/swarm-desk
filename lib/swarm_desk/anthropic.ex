defmodule SwarmDesk.Anthropic do
  @api_url "https://api.anthropic.com/v1/messages"

  def url, do: System.get_env("LLM_URL", @api_url)

  def headers do
    base = [{"anthropic-version", "2023-06-01"}]

    cond do
      System.get_env("LLM_URL") -> base
      key = System.get_env("ANTHROPIC_API_KEY") -> base ++ [{"x-api-key", key}]
      true -> raise "Set ANTHROPIC_API_KEY, or LLM_URL for a relay that adds auth"
    end
  end
end
