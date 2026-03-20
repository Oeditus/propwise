defmodule PropWise.PatternDetector do
  @moduledoc """
  Detects patterns in function ASTs that indicate good property-based testing candidates.
  """

  @doc """
  Analyzes a function and returns detected patterns that suggest property-based testing.
  """
  @spec detect_patterns(PropWise.FunctionInfo.t() | map()) :: [PropWise.Candidate.pattern()]
  def detect_patterns(function_info) do
    # Compute the stringified body once and thread it through all detectors.
    body_string = Macro.to_string(function_info.body)

    []
    |> maybe_add_pattern(
      :collection_operation,
      &detect_collection_operation/2,
      function_info,
      body_string
    )
    |> maybe_add_pattern(:transformation, &detect_transformation/2, function_info, body_string)
    |> maybe_add_pattern(:validation, &detect_validation/2, function_info, body_string)
    |> maybe_add_pattern(:algebraic, &detect_algebraic_structure/2, function_info, body_string)
    |> maybe_add_pattern(:encoder_decoder, &detect_encoder_decoder/2, function_info, body_string)
    |> maybe_add_pattern(:parser, &detect_parser/2, function_info, body_string)
    |> maybe_add_pattern(:numeric, &detect_numeric_algorithm/2, function_info, body_string)
  end

  @doc """
  Finds pairs of functions that appear to be inverses of each other.
  """
  @spec find_inverse_pairs([PropWise.FunctionInfo.t() | map()]) :: [map()]
  def find_inverse_pairs(functions) do
    inverse_name_pairs = [
      {"encode", "decode"},
      {"serialize", "deserialize"},
      {"parse", "generate"},
      {"parse", "format"},
      {"compress", "decompress"},
      {"encrypt", "decrypt"},
      {"to_", "from_"},
      {"pack", "unpack"},
      {"marshal", "unmarshal"}
    ]

    for {forward, inverse} <- inverse_name_pairs,
        f1 <- functions,
        f2 <- functions,
        f1.module == f2.module,
        f1.name != f2.name,
        name_matches?(f1.name, forward) and name_matches?(f2.name, inverse) do
      %{
        type: :inverse_pair,
        forward: {f1.module, f1.name, f1.arity},
        inverse: {f2.module, f2.name, f2.arity},
        suggestion: "Test round-trip property: #{f2.name}(#{f1.name}(x)) == x"
      }
    end
  end

  defp maybe_add_pattern(patterns, type, detector_fn, function_info, body_string) do
    case detector_fn.(function_info, body_string) do
      nil -> patterns
      reason -> [{type, reason} | patterns]
    end
  end

  # Detect collection operations (map, filter, sort, group)
  defp detect_collection_operation(_function_info, body_string) do
    patterns = [
      {~r/Enum\.(map|filter|sort|group|reduce|flat_map|chunk)/,
       "Uses Enum collection operations"},
      {~r/Stream\.(map|filter|chunk|take|drop)/, "Uses Stream operations"},
      {~r/\|> Enum\./, "Pipeline with Enum operations"},
      {~r/for .+ <- .+/, "List comprehension"}
    ]

    Enum.find_value(patterns, fn {regex, reason} ->
      if Regex.match?(regex, body_string), do: reason
    end)
  end

  # Detect data transformations via struct/map manipulation.
  # Deliberately excludes bare pipelines and `with` blocks which are too common.
  defp detect_transformation(function_info, _body_string) do
    cond do
      has_struct_manipulation?(function_info.body) ->
        "Struct transformation"

      has_map_manipulation?(function_info.body) ->
        "Map transformation"

      true ->
        nil
    end
  end

  # Detect validation functions based on Elixir naming conventions.
  # Relies on the strong convention of `?` suffix for predicates.
  defp detect_validation(function_info, _body_string) do
    name = to_string(function_info.name)

    cond do
      String.ends_with?(name, "?") ->
        "Boolean predicate"

      String.starts_with?(name, "valid") or String.contains?(name, "validate") ->
        "Validation function"

      String.starts_with?(name, "check") ->
        "Checking function"

      String.starts_with?(name, "is_") ->
        "Type check function"

      true ->
        nil
    end
  end

  # Detect algebraic structures (operations with associativity, commutativity, etc.)
  defp detect_algebraic_structure(function_info, _body_string) do
    name = to_string(function_info.name)
    segments = String.split(name, "_")

    algebraic_operations = ~w[merge concat combine union intersect compose append]

    if Enum.any?(algebraic_operations, fn op -> op in segments end) do
      "Potentially algebraic operation"
    end
  end

  # Detect encoder/decoder functions
  defp detect_encoder_decoder(function_info, _body_string) do
    name = to_string(function_info.name)
    segments = String.split(name, "_")

    encoding_segments = ~w[encode decode serialize deserialize]

    cond do
      Enum.any?(encoding_segments, fn kw -> kw in segments end) ->
        "Encoding/decoding function"

      name in ~w[to_json from_json to_xml from_xml] ->
        "Encoding/decoding function"

      true ->
        nil
    end
  end

  # Detect parser functions
  defp detect_parser(function_info, body_string) do
    name = to_string(function_info.name)
    segments = String.split(name, "_")

    cond do
      "parse" in segments ->
        "Parser function"

      String.contains?(body_string, ["Regex.run", "Regex.scan", "Regex.match?"]) ->
        "String parsing"

      true ->
        nil
    end
  end

  # Detect numeric algorithms via AST analysis instead of regex on stringified code.
  defp detect_numeric_algorithm(function_info, _body_string) do
    cond do
      has_math_module_calls?(function_info.body) ->
        "Math module operations"

      has_numeric_kernel_calls?(function_info.body) ->
        "Numeric operations"

      has_significant_arithmetic?(function_info.body) ->
        "Arithmetic operations"

      true ->
        nil
    end
  end

  # --- AST helper functions ---

  @map_write_fns [
    :put,
    :put_new,
    :put_new_lazy,
    :merge,
    :update,
    :update!,
    :delete,
    :drop,
    :take,
    :replace!,
    :split
  ]

  defp has_struct_manipulation?(ast) do
    {_ast, found} =
      Macro.prewalk(ast, false, fn
        {:%{}, _meta, fields} = node, _acc when is_list(fields) ->
          has_struct = Keyword.has_key?(fields, :__struct__)
          {node, has_struct}

        node, acc ->
          {node, acc}
      end)

    found
  end

  defp has_map_manipulation?(ast) do
    {_ast, found} =
      Macro.prewalk(ast, false, fn
        # Struct syntax: %Struct{...}
        {:%, _meta, _} = node, _ ->
          {node, true}

        # Map update syntax: %{map | key: val}
        {:%{}, _meta, [{:|, _, _} | _]} = node, _ ->
          {node, true}

        # Map write calls: Map.put, Map.merge, etc. (excludes reads like Map.get)
        {{:., _, [{:__aliases__, _, [:Map]}, fn_name]}, _, _} = node, _
        when fn_name in @map_write_fns ->
          {node, true}

        node, acc ->
          {node, acc}
      end)

    found
  end

  defp has_math_module_calls?(ast) do
    {_ast, found} =
      Macro.prewalk(ast, false, fn
        {{:., _, [:math, _]}, _, _} = node, _ -> {node, true}
        node, acc -> {node, acc}
      end)

    found
  end

  @numeric_kernel_fns [:div, :rem, :abs, :round, :floor, :ceil, :trunc]

  defp has_numeric_kernel_calls?(ast) do
    {_ast, found} =
      Macro.prewalk(ast, false, fn
        {fn_name, _, args} = node, acc when is_atom(fn_name) and is_list(args) ->
          {node, acc or fn_name in @numeric_kernel_fns}

        node, acc ->
          {node, acc}
      end)

    found
  end

  defp has_significant_arithmetic?(ast) do
    # Count actual binary arithmetic operator nodes in the AST.
    # Require at least 2 to filter out incidental uses like `length(x) + 1`.
    {_ast, count} =
      Macro.prewalk(ast, 0, fn
        {op, _, [_left, _right]} = node, count when op in [:+, :-, :*, :/] ->
          {node, count + 1}

        node, count ->
          {node, count}
      end)

    count >= 2
  end

  # Match function names against inverse pair patterns.
  # For prefix patterns ending in "_" (like "to_"), match as prefix only.
  # For other patterns, match as exact name or exact segment after splitting by "_".
  defp name_matches?(name, pattern) do
    name_str = to_string(name)

    if String.ends_with?(pattern, "_") do
      String.starts_with?(name_str, pattern)
    else
      name_str == pattern or
        name_str
        |> String.split("_")
        |> Enum.any?(&(&1 == pattern))
    end
  end
end
