defmodule SwarmDesk.Models do
  @clairic "@cf/cloudflare/clairic"
  @clef "@cf/cloudflare/clef"

  def clairic, do: @clairic
  def clef, do: @clef

  def run(model, body) do
    url = "#{ai_url()}/#{model}"
    headers = access_headers()

    pooled = [finch: [name: SwarmDesk.Finch, pool_timeout: 30_000], retry: :transient, max_retries: 5, retry_delay: fn n -> trunc(400 * :math.pow(2, n)) + :rand.uniform(400) end]
    fresh = [connect_options: [timeout: 8_000, transport_opts: [inet6: SwarmDesk.Http.ipv6?()]], retry: false]

    case post(url, body, headers, pooled) do
      {:error, %Req.TransportError{}} -> post(url, body, headers, fresh) |> unwrap(model)
      other -> unwrap(other, model)
    end
  end

  defp ai_url do
    System.get_env("AI_URL") || "https://api.cloudflare.com/client/v4/accounts/#{required_env("CLOUDFLARE_ACCOUNT_ID")}/ai/run"
  end

  defp access_headers do
    if System.get_env("AI_URL"), do: relay_headers(), else: [{"authorization", "Bearer " <> required_env("CLOUDFLARE_API_TOKEN")}]
  end

  defp required_env(name) do
    case System.get_env(name) do
      value when is_binary(value) and value != "" -> value
      _ -> raise "Set #{name}, or AI_URL for a relay such as the cloud Worker"
    end
  end

  defp relay_headers do
    with path when is_binary(path) and path != "" <- System.get_env("ACCESS_TOKEN_FILE"),
         {:ok, token} <- File.read(path) do
      [{"cf-access-token", String.trim(token)}]
    else
      _ -> []
    end
  end

  defp post(url, body, headers, opts), do: Req.post(url, [json: body, headers: headers, receive_timeout: 30_000] ++ opts)

  defp unwrap(response, model) do
    case response do
      {:ok, %{status: 200, body: %{"result" => result}}} -> {:ok, result}
      {:ok, %{body: body}} when is_binary(body) and binary_part(body, 0, min(byte_size(body), 15)) == "<!DOCTYPE html>" -> {:error, "#{model}: the AI relay returned a sign-in page (token missing or expired)"}
      {:ok, %{status: status, body: body}} -> {:error, "#{model} #{status}: #{inspect(body) |> String.slice(0, 160)}"}
      {:error, reason} -> {:error, "#{model}: #{inspect(reason)}"}
    end
  end
end
