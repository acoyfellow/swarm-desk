defmodule SwarmDesk.Code.Agent do
  alias SwarmDesk.Code.{LLM, TestPool, Workspace}

  @max_turns 30
  @max_output 6_000

  @tools [
    %{name: "list_files", description: "List every file in the repository, one path per line.", input_schema: %{type: "object", properties: %{}}},
    %{name: "read_file", description: "Read one file. Path is relative to the repository root.", input_schema: %{type: "object", properties: %{path: %{type: "string"}}, required: ["path"]}},
    %{name: "write_file", description: "Create or overwrite one file with the full content given.", input_schema: %{type: "object", properties: %{path: %{type: "string"}, content: %{type: "string"}}, required: ["path", "content"]}},
    %{name: "edit_file", description: "Replace one exact, unique snippet in a file with new text.", input_schema: %{type: "object", properties: %{path: %{type: "string"}, old: %{type: "string"}, new: %{type: "string"}}, required: ["path", "old", "new"]}},
    %{name: "grep", description: "Find lines matching a regular expression across the repository. Returns path:line:text.", input_schema: %{type: "object", properties: %{pattern: %{type: "string"}}, required: ["pattern"]}},
    %{name: "run_tests", description: "Run the project's test suite (node --test) and return its output and exit code.", input_schema: %{type: "object", properties: %{}}},
    %{name: "done", description: "Finish. Call this once the work is complete and the tests pass.", input_schema: %{type: "object", properties: %{summary: %{type: "string"}}, required: ["summary"]}}
  ]

  def default_spec, do: %{"name" => "default", "model" => LLM.model(), "max_turns" => @max_turns, "max_tokens" => 4000, "tools" => Enum.map(@tools, & &1.name)}

  def run(%{id: id, dir: dir, task: task, on_event: on_event} = args) do
    spec = Map.get(args, :spec) || default_spec()
    tools = Enum.filter(@tools, &(&1.name in spec["tools"]))
    system = system_prompt(task, "run_tests" in spec["tools"])
    messages = [%{role: "user", content: "Do the task. Start by looking at the repository."}]
    started = System.monotonic_time(:millisecond)
    state = %{id: id, dir: dir, on_event: on_event, spec: spec, tools: tools, turns: 0, tools_used: 0, tests_run: 0, usage: %{in: 0, out: 0}, started: started}
    loop(system, messages, state)
  end

  defp loop(_system, _messages, %{turns: turns, spec: %{"max_turns" => max}} = state) when turns >= max, do: finish(state, :out_of_turns, "stopped after #{max} turns")

  defp loop(system, messages, state) do
    case LLM.chat(system, messages, state.tools, state.spec["max_tokens"], state.spec["model"]) do
      {:error, reason} ->
        finish(state, :model_error, reason)

      {:ok, %{stop: "refusal", usage: usage}} ->
        finish(%{state | turns: state.turns + 1, usage: %{in: state.usage.in + (usage["input_tokens"] || 0), out: state.usage.out + (usage["output_tokens"] || 0)}}, :refused, "the model refused this turn")

      {:ok, %{stop: "max_tokens", content: content, usage: usage}} ->
        state = %{state | turns: state.turns + 1, usage: %{in: state.usage.in + (usage["input_tokens"] || 0), out: state.usage.out + (usage["output_tokens"] || 0)}}
        if Enum.any?(content, &(&1["type"] == "tool_use")) do
          {results, state} = content |> Enum.filter(&(&1["type"] == "tool_use")) |> Enum.map_reduce(state, &call_tool/2)
          loop(system, messages ++ [%{role: "assistant", content: content}, %{role: "user", content: results}], state)
        else
          finish(state, :ran_out_of_tokens, "the model hit max_tokens (#{state.spec["max_tokens"]}) before acting")
        end

      {:ok, %{content: content, usage: usage}} ->
        state = %{state | turns: state.turns + 1, usage: %{in: state.usage.in + (usage["input_tokens"] || 0), out: state.usage.out + (usage["output_tokens"] || 0)}}
        calls = Enum.filter(content, &(&1["type"] == "tool_use"))

        cond do
          calls == [] ->
            finish(state, :stopped_talking, content |> Enum.filter(&(&1["type"] == "text")) |> Enum.map_join(" ", & &1["text"]) |> String.slice(0, 300))

          done = Enum.find(calls, &(&1["name"] == "done")) ->
            finish(state, :done, get_in(done, ["input", "summary"]) || "")

          true ->
            {results, state} = Enum.map_reduce(calls, state, &call_tool/2)
            loop(system, messages ++ [%{role: "assistant", content: content}, %{role: "user", content: results}], state)
        end
    end
  end

  defp call_tool(%{"id" => tool_id, "name" => name, "input" => input}, state) do
    state.on_event.(%{agent: state.id, kind: "tool", tool: name, arg: summarize(name, input), turn: state.turns})
    allowed? = name in state.spec["tools"]
    {output, state} = if allowed?, do: tool(name, input, %{state | tools_used: state.tools_used + 1}), else: {"error: tool #{name} is not available to this agent", state}
    {%{type: "tool_result", tool_use_id: tool_id, content: clip(output)}, state}
  end

  defp tool("list_files", _input, state), do: {list(state.dir) |> Enum.join("\n"), state}

  defp tool("read_file", %{"path" => path}, state) do
    with {:ok, full} <- Workspace.resolve(state.dir, path), {:ok, text} <- File.read(full) do
      {text, state}
    else
      {:error, reason} -> {"error: #{inspect(reason)}", state}
    end
  end

  defp tool("write_file", %{"path" => path, "content" => content}, state) do
    with {:ok, full} <- Workspace.resolve(state.dir, path), :ok <- File.mkdir_p(Path.dirname(full)), :ok <- File.write(full, content) do
      {"wrote #{byte_size(content)} bytes to #{path}", state}
    else
      {:error, reason} -> {"error: #{inspect(reason)}", state}
    end
  end

  defp tool("edit_file", %{"path" => path, "old" => old, "new" => new}, state) do
    with {:ok, full} <- Workspace.resolve(state.dir, path), {:ok, text} <- File.read(full) do
      case length(String.split(text, old)) - 1 do
        1 -> (File.write!(full, String.replace(text, old, new)); {"edited #{path}", state})
        0 -> {"error: the old text was not found in #{path}", state}
        n -> {"error: the old text appears #{n} times in #{path}; give a longer unique snippet", state}
      end
    else
      {:error, reason} -> {"error: #{inspect(reason)}", state}
    end
  end

  defp tool("grep", %{"pattern" => pattern}, state) do
    case Regex.compile(pattern) do
      {:ok, regex} ->
        hits =
          for path <- list(state.dir), {line, n} <- state.dir |> Path.join(path) |> File.read!() |> String.split("\n") |> Enum.with_index(1), Regex.match?(regex, line), do: "#{path}:#{n}:#{line}"

        {hits |> Enum.take(80) |> Enum.join("\n") |> then(&if(&1 == "", do: "no matches", else: &1)), state}

      {:error, _} ->
        {"error: bad regular expression", state}
    end
  end

  defp tool("run_tests", _input, state) do
    result = TestPool.run(state.dir, ["--test"])
    state.on_event.(%{agent: state.id, kind: "tests", exit: result.exit, turn: state.turns})
    {"exit #{result.exit}\n#{tail(result.output)}", %{state | tests_run: state.tests_run + 1}}
  end

  defp tool(name, _input, state), do: {"error: tool #{name} is not available to this agent", state}

  defp finish(state, outcome, note) do
    result = %{agent: state.id, outcome: outcome, note: note, turns: state.turns, tools_used: state.tools_used, tests_run: state.tests_run, usage: state.usage, ms: System.monotonic_time(:millisecond) - state.started}
    state.on_event.(Map.put(result, :kind, "finished"))
    result
  end

  defp list(dir) do
    Path.wildcard(Path.join(dir, "**/*"), match_dot: false) |> Enum.filter(&File.regular?/1) |> Enum.map(&Path.relative_to(&1, dir)) |> Enum.reject(&String.starts_with?(&1, "node_modules/")) |> Enum.sort()
  end

  defp summarize("read_file", %{"path" => p}), do: p
  defp summarize("write_file", %{"path" => p}), do: p
  defp summarize("edit_file", %{"path" => p}), do: p
  defp summarize("grep", %{"pattern" => p}), do: String.slice(p, 0, 40)
  defp summarize(_, _), do: ""

  defp clip(text) when byte_size(text) > @max_output, do: binary_part(text, 0, @max_output) <> "\n…(cut)"
  defp clip(text), do: text

  defp tail(text) do
    lines = String.split(text, "\n")
    lines |> Enum.take(-60) |> Enum.join("\n")
  end

  defp system_prompt(task, can_test?) do
    """
    You are a coding agent working alone in your own copy of a TypeScript repository. You can only act through the tools.
    Node 24 runs the .ts files directly with no build step and nothing installed. The test command is node --test.

    Task: #{task.title}
    #{task.why}

    Files this task should touch: #{Enum.join(task.footprint, ", ")}

    Acceptance criteria (all must hold):
    #{Enum.map_join(task.acceptance, "\n", &"- #{&1}")}

    Project conventions:
    #{task.conventions}

    #{if can_test?, do: "Work method: read the relevant files, make the change, write the tests the criteria ask for, run the tests, fix failures, then call done.\n    Every existing test must keep passing. Do not call done until run_tests exits 0.", else: "Work method: read the relevant files, make the change, write the tests the criteria ask for, check your work by reading it, then call done.\n    You cannot run the tests. Every existing test must keep passing."}
    """
  end
end
