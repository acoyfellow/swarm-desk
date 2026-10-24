defmodule SwarmDesk.Proofs.Prover do
  alias SwarmDesk.{Models, Opus}
  alias SwarmDesk.Proofs.Kernel

  @strategies %{
    "simp" => "the goal closes by rewriting with standard simp lemmas",
    "omega" => "the goal is linear arithmetic over natural numbers",
    "induction" => "the goal needs induction on a natural number or a list",
    "cases" => "the goal needs unfolding a definition and splitting on an if-then-else",
    "decide" => "the goal is a finite decidable fact"
  }

  @system "You write Lean 4 tactic proofs using only core Lean, no Mathlib. Reply with ONLY the tactic lines that go after `:= by`. No prose, no code fences, no sorry."

  def prove(:alone, {id, statement}, dir, tries), do: loop(id, statement, nil, dir, tries)

  def prove(:guided, {id, statement}, dir, tries) do
    {hint, odds} = strategy(statement)
    loop(id, statement, {hint, odds}, dir, tries)
  end

  defp strategy(statement) do
    body = %{"state" => statement, "questions" => %{"s" => %{"type" => "choice", "instructions" => "Which proof strategy closes this Lean theorem?", "criteria" => @strategies}}}

    case Models.run(Models.clef(), body) do
      {:ok, %{"answers" => %{"s" => %{"choice" => c, "probabilities" => p}}}} -> {c, p}
      _ -> {nil, %{}}
    end
  end

  defp loop(id, statement, hint, dir, tries) do
    started = System.monotonic_time(:millisecond)
    result = attempt(id, statement, hint, dir, tries, 1, nil)
    Map.merge(result, %{id: id, hint: hint && elem(hint, 0), ms: System.monotonic_time(:millisecond) - started})
  end

  defp attempt(_id, _statement, _hint, _dir, max, n, last) when n > max, do: %{proved: false, calls: max, last_error: last}

  defp attempt(id, statement, hint, dir, max, n, last) do
    prompt = prompt(statement, hint, last)

    case Opus.ask(@system, prompt) do
      {:ok, text} ->
        proof = clean(text)

        case Kernel.check(id, statement, proof, dir) do
          :accepted -> %{proved: true, calls: n, proof: proof}
          {:rejected, err} -> attempt(id, statement, hint, dir, max, n + 1, err)
        end

      {:error, err} ->
        attempt(id, statement, hint, dir, max, n + 1, err)
    end
  end

  defp prompt(statement, hint, last) do
    [
      "Prove:\n" <> statement,
      hint && "A strategy model suggests: #{elem(hint, 0)} (odds #{inspect(elem(hint, 1))}). Start from it unless it clearly does not fit.",
      last && "Your last attempt failed with:\n" <> last
    ]
    |> Enum.reject(&is_nil/1)
    |> Enum.join("\n\n")
  end

  defp clean(text), do: text |> String.replace(~r/```[a-z]*\n?/, "") |> String.trim()
end
