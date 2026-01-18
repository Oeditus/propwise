defmodule PropWise.PurityAnalyzer do
  @moduledoc """
  Analyzes function ASTs to determine if they are pure (no side effects).
  """

  @side_effect_modules [
    "IO",
    "File",
    "GenServer",
    "Agent",
    "Task",
    "Process",
    "Ecto.Repo",
    "Ecto.Query",
    "HTTPoison",
    "Tesla",
    "Req",
    "System",
    ":ets",
    ":dets",
    ":mnesia",
    "Logger",
    "Registry",
    "DynamicSupervisor",
    "Supervisor"
  ]

  @side_effect_functions [
    {:send, 2},
    {:spawn, 1},
    {:spawn, 3},
    {:spawn_link, 1},
    {:spawn_link, 3},
    {:put_in, 2},
    {:update_in, 2},
    {:get_and_update_in, 2}
  ]

  @doc """
  Analyzes a function to determine if it's pure.
  Returns {:pure, reasons} or {:impure, side_effects}.
  """
  def analyze(function_info) do
    side_effects = find_side_effects(function_info.body)

    if Enum.empty?(side_effects) do
      {:pure, []}
    else
      {:impure, side_effects}
    end
  end

  @doc """
  Returns true if the function appears pure.
  """
  def pure?(function_info) do
    match?({:pure, _}, analyze(function_info))
  end

  defp find_side_effects(ast) do
    {_ast, effects} =
      Macro.prewalk(ast, [], fn node, acc ->
        case detect_side_effect(node) do
          nil -> {node, acc}
          effect -> {node, [effect | acc]}
        end
      end)

    Enum.reverse(effects)
  end

  defp detect_side_effect(
         {{:., _meta, [{:__aliases__, _meta2, module_parts}, function]}, _meta3, _args}
       ) do
    module_name = Enum.join(module_parts, ".")

    if side_effect_module?(module_name) do
      {:module_call, module_name, function}
    end
  end

  defp detect_side_effect({{:., _meta, [module, function]}, _meta2, args})
       when is_atom(module) and is_list(args) do
    module_name = to_string(module)

    if side_effect_module?(module_name) do
      {:module_call, module_name, function}
    end
  end

  defp detect_side_effect({function, _meta, args})
       when is_atom(function) and is_list(args) do
    if {function, length(args)} in @side_effect_functions do
      {:function_call, function, length(args)}
    end
  end

  defp detect_side_effect({:receive, _meta, _}) do
    {:receive_block}
  end

  defp detect_side_effect({:!, _meta, _}) do
    {:bang_operator}
  end

  defp detect_side_effect(_), do: nil

  defp side_effect_module?(module_name) do
    Enum.any?(@side_effect_modules, fn pattern ->
      String.starts_with?(module_name, pattern)
    end)
  end
end
