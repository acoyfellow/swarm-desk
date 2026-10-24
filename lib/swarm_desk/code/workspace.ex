defmodule SwarmDesk.Code.Workspace do
  def prepare_base(seed_dir, root) do
    base = Path.join(root, "base")
    File.rm_rf!(root)
    File.mkdir_p!(base)
    File.cp_r!(seed_dir, base)
    base
  end

  def add_worktree(base, name) do
    path = Path.join(Path.dirname(base), name)
    File.cp_r!(base, path)
    path
  end

  def diff(path) do
    base = base_of(path)
    {out, _} = System.cmd("git", ["diff", "--no-index", "--no-color", base, path], stderr_to_stdout: true)
    String.replace(out, [base, path], "")
  end

  def changed_files(path) do
    base = base_of(path)
    {out, _} = System.cmd("git", ["diff", "--no-index", "--name-only", base, path], stderr_to_stdout: true)
    out |> String.split("\n", trim: true) |> Enum.map(&(&1 |> String.replace_prefix(path <> "/", "") |> String.replace_prefix(base <> "/", ""))) |> Enum.uniq()
  end

  def resolve(root, relative) do
    full = Path.expand(relative, root)
    if full == root or String.starts_with?(full, root <> "/"), do: {:ok, full}, else: {:error, "path escapes the workspace: #{relative}"}
  end

  defp base_of(path), do: Path.join(Path.dirname(path), "base")
end
