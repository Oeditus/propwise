defmodule PropWise.PatternDetector do
  @moduledoc """
  Detects patterns in function ASTs that indicate good property-based testing candidates.
  """

  @doc """
  Analyzes a function and returns detected patterns that suggest property-based testing.
  """
  def detect_patterns(function_info) do
    []
    |> maybe_add_pattern(:collection_operation, &detect_collection_operation/1, function_info)
    |> maybe_add_pattern(:transformation, &detect_transformation/1, function_info)
    |> maybe_add_pattern(:validation, &detect_validation/1, function_info)
    |> maybe_add_pattern(:algebraic, &detect_algebraic_structure/1, function_info)
    |> maybe_add_pattern(:encoder_decoder, &detect_encoder_decoder/1, function_info)
    |> maybe_add_pattern(:parser, &detect_parser/1, function_info)
    |> maybe_add_pattern(:numeric, &detect_numeric_algorithm/1, function_info)
  end

  @doc """
  Finds pairs of functions that appear to be inverses of each other.
  """
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

  defp maybe_add_pattern(patterns, type, detector_fn, function_info) do
    case detector_fn.(function_info) do
      nil -> patterns
      reason -> [{type, reason} | patterns]
    end
  end

  # Detect collection operations (map, filter, sort, group)
  defp detect_collection_operation(function_info) do
    patterns = [
      {~r/Enum\.(map|filter|sort|group|reduce|flat_map|chunk)/,
       "Uses Enum collection operations"},
      {~r/Stream\.(map|filter|chunk|take|drop)/, "Uses Stream operations"},
      {~r/\|> Enum\./, "Pipeline with Enum operations"},
      {~r/for .+ <- .+/, "List comprehension"}
    ]

    body_string = Macro.to_string(function_info.body)

    Enum.find_value(patterns, fn {regex, reason} ->
      if Regex.match?(regex, body_string), do: reason
    end)
  end

  # Detect data transformations
  defp detect_transformation(function_info) do
    body_string = Macro.to_string(function_info.body)

    cond do
      String.contains?(body_string, ["|>", "with"]) ->
        "Pipeline transformation"

      has_struct_manipulation?(function_info.body) ->
        "Struct transformation"

      has_map_manipulation?(function_info.body) ->
        "Map transformation"

      true ->
        nil
    end
  end

  # Detect validation functions
  defp detect_validation(function_info) do
    name = to_string(function_info.name)

    cond do
      String.starts_with?(name, "valid") or String.contains?(name, "validate") ->
        "Validation function"

      String.starts_with?(name, "check") ->
        "Checking function"

      returns_boolean?(function_info.body) ->
        "Boolean predicate"

      true ->
        nil
    end
  end

  # Detect algebraic structures (operations with associativity, commutativity, etc.)
  defp detect_algebraic_structure(function_info) do
    name = to_string(function_info.name)

    algebraic_operations = [
      "merge",
      "concat",
      "combine",
      "union",
      "intersect",
      "compose",
      "append",
      "add",
      "multiply"
    ]

    if Enum.any?(algebraic_operations, &String.contains?(name, &1)) do
      "Potentially algebraic operation"
    end
  end

  # Detect encoder/decoder functions
  defp detect_encoder_decoder(function_info) do
    name = to_string(function_info.name)

    encoding_keywords = ["encode", "decode", "serialize", "deserialize", "to_json", "from_json"]

    if Enum.any?(encoding_keywords, &String.contains?(name, &1)) do
      "Encoding/decoding function"
    end
  end

  # Detect parser functions
  defp detect_parser(function_info) do
    name = to_string(function_info.name)
    body_string = Macro.to_string(function_info.body)

    cond do
      String.contains?(name, "parse") ->
        "Parser function"

      String.contains?(body_string, ["String.split", "Regex.run", "Regex.scan"]) ->
        "String parsing"

      true ->
        nil
    end
  end

  # Detect numeric algorithms
  defp detect_numeric_algorithm(function_info) do
    body_string = Macro.to_string(function_info.body)

    numeric_patterns = [
      {~r/\b(div|rem|abs|round|floor|ceil|sqrt|pow)\b/, "Numeric operations"},
      {~r/\+|\-|\*|\//, "Arithmetic operations"}
    ]

    Enum.find_value(numeric_patterns, fn {regex, reason} ->
      if Regex.match?(regex, body_string), do: reason
    end)
  end

  # Helper functions
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
        {:%, _meta, _} = node, _ -> {node, true}
        {:%{}, _meta, _} = node, _ -> {node, true}
        {{:., _, [Map, _]}, _, _} = node, _ -> {node, true}
        node, acc -> {node, acc}
      end)

    found
  end

  defp returns_boolean?(ast) do
    body_string = Macro.to_string(ast)

    String.contains?(body_string, [
      "true",
      "false",
      "and ",
      "or ",
      "not ",
      "==",
      "!=",
      ">",
      "<",
      ">=",
      "<=",
      "is_"
    ])
  end

  defp name_matches?(name, pattern) do
    name_str = to_string(name)
    String.contains?(name_str, pattern)
  end
end
