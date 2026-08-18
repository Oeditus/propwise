defmodule PropWise.PurityAnalyzer do
  @moduledoc """
  Analyzes function ASTs (MetaAST from Metastatic) to determine if they are pure (no side effects).

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

  alias Metastatic.Adapters.Elixir.ToMeta
  alias Metastatic.Semantic.Enricher

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
    {:spawn_link, 3}
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
  @spec analyze(PropWise.FunctionInfo.t() | map(), keyword()) ::
          {:pure, []} | {:impure, [tuple()]}
  def analyze(function_info, opts \\ []) do
    side_effect_calls = Keyword.get(opts, :side_effect_calls, @default_side_effect_calls)

    side_effect_functions =
      Keyword.get(opts, :side_effect_functions, @default_side_effect_functions)

    meta_ast = ensure_meta_ast(function_info.body)
    side_effects = find_side_effects(meta_ast, side_effect_calls, side_effect_functions)

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
  @spec pure?(PropWise.FunctionInfo.t() | map(), keyword()) :: boolean()
  def pure?(function_info, opts \\ []) do
    match?({:pure, _}, analyze(function_info, opts))
  end

  # ----- Helpers -----

  @doc false
  def ensure_meta_ast(ast) do
    cond do
      meta_ast?(ast) ->
        ast

      is_list(ast) ->
        case Enum.map(ast, &ensure_meta_ast/1) do
          [single] -> single
          items -> {:block, [], items}
        end

      true ->
        case ToMeta.transform(ast) do
          {:ok, meta_ast, _metadata} ->
            Enricher.enrich_tree(meta_ast, :elixir)

          _ ->
            ast
        end
    end
  end

  @meta_types [
    :literal,
    :variable,
    :binary_op,
    :unary_op,
    :function_call,
    :conditional,
    :pattern_match,
    :block,
    :list,
    :map,
    :tuple,
    :container,
    :function_def,
    :comprehension,
    :generator,
    :lambda,
    :pair,
    :match_arm,
    :import,
    :type_annotation,
    :return,
    :try,
    :catch,
    :throw,
    :raise,
    :collection_op
  ]

  defp meta_ast?({type, meta, _}) when type in @meta_types and is_list(meta), do: true
  defp meta_ast?(_), do: false

  defp find_side_effects(ast, side_effect_calls, side_effect_functions) do
    {_ast, effects} =
      Metastatic.traverse(
        ast,
        [],
        fn node, acc ->
          case detect_side_effect(node, side_effect_calls, side_effect_functions) do
            nil -> {node, acc}
            effect -> {node, [effect | acc]}
          end
        end,
        fn node, acc -> {node, acc} end
      )

    Enum.reverse(effects)
  end

  defp detect_side_effect({:function_call, meta, args}, side_calls, side_funcs)
       when is_list(args) do
    call_name = to_string(meta[:name] || "")
    arity = length(args)

    op_kind = meta[:op_kind]
    domain = op_kind && op_kind[:domain]

    cond do
      domain in [:db, :http, :cache, :file, :auth, :queue, :external_api] ->
        {:semantic_op, domain, op_kind[:operation] || :op}

      call_name == "receive" ->
        {:receive_block}

      String.contains?(call_name, ".") ->
        {mod_str, fn_str} = split_call_name(call_name)
        module = parse_module(mod_str)
        func = String.to_atom(fn_str)

        if side_effect_call?(module, func, arity, side_calls) do
          {:module_call, module, func, arity}
        end

      true ->
        func = String.to_atom(call_name)

        if {func, arity} in side_funcs do
          {:function_call, func, arity}
        end
    end
  end

  defp detect_side_effect(_node, _calls, _funcs), do: nil

  defp split_call_name(call_name) do
    parts = String.split(call_name, ".")
    fn_name = List.last(parts)
    mod_parts = Enum.drop(parts, -1)
    mod_str = Enum.join(mod_parts, ".")
    {mod_str, fn_name}
  end

  defp parse_module(":" <> atom_str), do: String.to_atom(atom_str)

  defp parse_module(mod_str) do
    if String.starts_with?(mod_str, ":") do
      String.to_atom(String.trim_leading(mod_str, ":"))
    else
      parts = String.split(mod_str, ".")

      if Enum.all?(parts, &valid_alias?/1) do
        Module.concat(parts)
      else
        String.to_atom(mod_str)
      end
    end
  end

  defp valid_alias?(str), do: Regex.match?(~r/^[A-Z][a-zA-Z0-9_]*$/, str)

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
