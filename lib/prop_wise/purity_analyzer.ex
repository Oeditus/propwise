defmodule PropWise.PurityAnalyzer do
  @moduledoc """
  Analyzes function ASTs to determine if they are pure (no side effects).

  ## Configuration

  Side effect detection can be customized by providing options:

      analyze(function_info, side_effect_calls: [...], side_effect_functions: [...])

  ### Side Effect Calls

  List of `{module, function, arity}` tuples that indicate side effects.
  Supports wildcards:
  - `{Module, :*, :*}` - All functions in module
  - `{Module, :function, :*}` - All arities of function

  ### Side Effect Functions

  List of `{function, arity}` tuples for bare function calls that indicate side effects.
  """

  # Default side effect module calls
  @default_side_effect_calls [
    # I/O operations
    {IO, :*, :*},
    {File, :*, :*},
    {Logger, :*, :*},
    # Process operations
    {GenServer, :*, :*},
    {Agent, :*, :*},
    {Task, :*, :*},
    {Process, :send, :*},
    {Process, :send_after, :*},
    {Process, :exit, :*},
    {Process, :flag, :*},
    {Process, :put, :*},
    {Process, :register, :*},
    {Process, :unregister, :*},
    # Database operations
    {Ecto.Repo, :*, :*},
    {Ecto.Query, :*, :*},
    # HTTP operations
    {Req, :*, :*},
    # System operations
    {System, :*, :*},
    {:ets, :*, :*},
    {:dets, :*, :*},
    {:mnesia, :*, :*},
    # Supervision
    {Registry, :*, :*},
    {DynamicSupervisor, :*, :*},
    {Supervisor, :*, :*},
    # Telemetry
    {:telemetry, :span, 3}
  ]

  # Default side effect bare functions
  @default_side_effect_functions [
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
  Returns `{:pure, []}` or `{:impure, side_effects}`.

  ## Options

    * `:side_effect_calls` - List of `{module, function, arity}` tuples (default: built-in list)
    * `:side_effect_functions` - List of `{function, arity}` tuples (default: built-in list)

  ## Examples

      analyze(function_info)
      analyze(function_info, side_effect_calls: [{MyModule, :impure_func, 1}])
  """
  def analyze(function_info, opts \\ []) do
    side_effect_calls = Keyword.get(opts, :side_effect_calls, @default_side_effect_calls)

    side_effect_functions =
      Keyword.get(opts, :side_effect_functions, @default_side_effect_functions)

    side_effects = find_side_effects(function_info.body, side_effect_calls, side_effect_functions)

    if Enum.empty?(side_effects) do
      {:pure, []}
    else
      {:impure, side_effects}
    end
  end

  @doc """
  Returns true if the function appears pure.

  Accepts the same options as `analyze/2`.
  """
  def pure?(function_info, opts \\ []) do
    match?({:pure, _}, analyze(function_info, opts))
  end

  # Private helper functions

  defp find_side_effects(ast, side_effect_calls, side_effect_functions) do
    {_ast, effects} =
      Macro.prewalk(ast, [], fn node, acc ->
        case detect_side_effect(node, side_effect_calls, side_effect_functions) do
          nil -> {node, acc}
          effect -> {node, [effect | acc]}
        end
      end)

    Enum.reverse(effects)
  end

  # Detect module calls like Module.function(args)
  defp detect_side_effect(
         {{:., _meta, [{:__aliases__, _meta2, module_parts}, function]}, _meta3, args},
         side_effect_calls,
         _side_effect_functions
       )
       when is_list(args) do
    module = Module.concat(module_parts)
    arity = length(args)

    if side_effect_call?(module, function, arity, side_effect_calls) do
      {:module_call, module, function, arity}
    end
  end

  # Detect atom module calls like :ets.insert(...) or :telemetry.span(...)
  defp detect_side_effect(
         {{:., _meta, [module, function]}, _meta2, args},
         side_effect_calls,
         _side_effect_functions
       )
       when is_atom(module) and is_list(args) do
    arity = length(args)

    if side_effect_call?(module, function, arity, side_effect_calls) do
      {:module_call, module, function, arity}
    end
  end

  # Detect bare function calls like send(...)
  defp detect_side_effect(
         {function, _meta, args},
         _side_effect_calls,
         side_effect_functions
       )
       when is_atom(function) and is_list(args) do
    arity = length(args)

    if {function, arity} in side_effect_functions do
      {:function_call, function, arity}
    end
  end

  # Detect receive blocks
  defp detect_side_effect({:receive, _meta, _}, _side_effect_calls, _side_effect_functions) do
    {:receive_block}
  end

  # Detect bang operator (convention for side effects)
  defp detect_side_effect({:!, _meta, _}, _side_effect_calls, _side_effect_functions) do
    {:bang_operator}
  end

  defp detect_side_effect(_node, _side_effect_calls, _side_effect_functions), do: nil

  # Check if a module call matches any side effect pattern
  defp side_effect_call?(module, function, arity, side_effect_calls) do
    Enum.any?(side_effect_calls, fn
      # Exact match: {Module, :function, arity}
      {^module, ^function, ^arity} -> true
      # Module wildcard: {Module, :*, :*}
      {^module, :*, :*} -> true
      # Function wildcard: {Module, :function, :*}
      {^module, ^function, :*} -> true
      # No match
      _ -> false
    end)
  end
end
