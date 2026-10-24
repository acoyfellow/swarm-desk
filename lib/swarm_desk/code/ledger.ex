defmodule SwarmDesk.Code.Ledger do
  @keep 500

  def record(entry) do
    case remote() do
      nil -> write_local([entry | read_local()] |> Enum.take(@keep))
      url -> Req.post(url <> "/record", json: entry, retry: false, receive_timeout: 10_000)
    end

    :ok
  end

  def list do
    case remote() do
      nil -> read_local()
      url -> fetch_remote(url)
    end
  end

  def summary do
    runs = list()

    %{
      runs: length(runs),
      usd: runs |> Enum.map(&(&1["usd"] || 0)) |> Enum.sum() |> Float.round(2),
      agents: runs |> Enum.map(&(&1["agents"] || 0)) |> Enum.sum(),
      shipped: runs |> Enum.map(&(&1["shipped"] || 0)) |> Enum.sum(),
      wrong_ships: runs |> Enum.map(&(&1["wrong_ships"] || 0)) |> Enum.sum(),
      recent: Enum.take(runs, 20)
    }
  end

  defp remote, do: System.get_env("LEDGER_URL")

  defp fetch_remote(url) do
    case Req.get(url <> "/list", retry: false, receive_timeout: 10_000) do
      {:ok, %{status: 200, body: runs}} when is_list(runs) -> runs
      _ -> []
    end
  end

  defp path, do: System.get_env("LEDGER_FILE", Path.expand(".real/code-ledger.json"))

  defp read_local do
    with {:ok, text} <- File.read(path()), {:ok, runs} when is_list(runs) <- Jason.decode(text) do
      runs
    else
      _ -> []
    end
  end

  defp write_local(runs) do
    File.mkdir_p!(Path.dirname(path()))
    File.write!(path(), Jason.encode!(runs))
  end
end
