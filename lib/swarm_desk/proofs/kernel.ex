defmodule SwarmDesk.Proofs.Kernel do
  @banned ~w(sorry admit axiom native_decide)

  def check(id, statement, proof, dir) do
    cond do
      Enum.any?(@banned, &String.contains?(proof, &1)) -> {:rejected, "banned word"}
      true -> run_lean(id, statement <> " := by\n" <> indent(proof), dir)
    end
  end

  defp indent(proof), do: proof |> String.split("\n") |> Enum.map_join("\n", &("  " <> &1))

  defp run_lean(id, source, dir) do
    file = Path.join(dir, "#{id}_#{System.unique_integer([:positive])}.lean")
    File.write!(file, source <> "\n")

    case System.cmd("lean", [file], stderr_to_stdout: true) do
      {_, 0} -> :accepted
      {out, _} -> {:rejected, String.slice(out, 0, 600)}
    end
  end
end
