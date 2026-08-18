defmodule PropWise.PatternDetector do
  @moduledoc """
  Detects patterns in function MetaASTs that indicate good property-based testing candidates.
  """

  alias PropWise.PurityAnalyzer

  @doc """
  Analyzes a function and returns detected patterns that suggest property-based testing.
  """
  @spec detect_patterns(PropWise.FunctionInfo.t() | map()) :: [PropWise.Candidate.pattern()]
  def detect_patterns(function_info) do
    meta_ast = PurityAnalyzer.ensure_meta_ast(function_info.body)
    body_string = to_body_string(meta_ast)

    []
    |> maybe_add_pattern(
      :collection_operation,
      &detect_collection_operation/3,
      function_info,
      meta_ast,
      body_string
    )
    |> maybe_add_pattern(
      :transformation,
      &detect_transformation/3,
      function_info,
      meta_ast,
      body_string
    )
    |> maybe_add_pattern(
      :validation,
      &detect_validation/3,
      function_info,
      meta_ast,
      body_string
    )
    |> maybe_add_pattern(
      :algebraic,
      &detect_algebraic_structure/3,
      function_info,
      meta_ast,
      body_string
    )
    |> maybe_add_pattern(
      :encoder_decoder,
      &detect_encoder_decoder/3,
      function_info,
      meta_ast,
      body_string
    )
    |> maybe_add_pattern(
      :parser,
      &detect_parser/3,
      function_info,
      meta_ast,
      body_string
    )
    |> maybe_add_pattern(
      :numeric,
      &detect_numeric_algorithm/3,
      function_info,
      meta_ast,
      body_string
    )
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

  defp maybe_add_pattern(patterns, type, detector_fn, function_info, meta_ast, body_string) do
    case detector_fn.(function_info, meta_ast, body_string) do
      nil -> patterns
      reason -> [{type, reason} | patterns]
    end
  end

  # Detect collection operations (map, filter, sort, group)
  defp detect_collection_operation(_info, meta_ast, body_string) do
    has_collection_node =
      Metastatic.postwalker(meta_ast)
      |> Enum.any?(fn
        {:collection_op, _, _} ->
          true

        {:comprehension, _, _} ->
          true

        {:function_call, meta, _} ->
          name = to_string(meta[:name] || "")
          String.starts_with?(name, "Enum.") or String.starts_with?(name, "Stream.")

        _ ->
          false
      end)

    patterns = [
      {~r/Enum\.(map|filter|sort|group|reduce|flat_map|chunk)/,
       "Uses Enum collection operations"},
      {~r/Stream\.(map|filter|chunk|take|drop)/, "Uses Stream operations"},
      {~r/\|> Enum\./, "Pipeline with Enum operations"},
      {~r/for .+ <- .+/, "List comprehension"}
    ]

    if has_collection_node do
      "Uses Enum collection operations"
    else
      Enum.find_value(patterns, fn {regex, reason} ->
        if Regex.match?(regex, body_string), do: reason
      end)
    end
  end

  # Detect data transformations via struct/map manipulation.
  # Deliberately excludes bare pipelines and `with` blocks which are too common.
  defp detect_transformation(_function_info, meta_ast, _body_string) do
    cond do
      has_struct_manipulation?(meta_ast) ->
        "Struct transformation"

      has_map_manipulation?(meta_ast) ->
        "Map transformation"

      true ->
        nil
    end
  end

  # Detect validation functions based on Elixir naming conventions.
  # Relies on the strong convention of `?` suffix for predicates.
  defp detect_validation(function_info, _meta_ast, _body_string) do
    name = safe_to_string(function_info.name)

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
  defp detect_algebraic_structure(function_info, _meta_ast, _body_string) do
    name = safe_to_string(function_info.name)
    segments = String.split(name, "_")

    algebraic_operations = ~w[merge concat combine union intersect compose append]

    if Enum.any?(algebraic_operations, fn op -> op in segments end) do
      "Potentially algebraic operation"
    end
  end

  # Detect encoder/decoder functions
  defp detect_encoder_decoder(function_info, _meta_ast, _body_string) do
    name = safe_to_string(function_info.name)
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
  defp detect_parser(function_info, meta_ast, body_string) do
    name = safe_to_string(function_info.name)
    segments = String.split(name, "_")

    has_regex =
      Metastatic.postwalker(meta_ast)
      |> Enum.any?(fn
        {:function_call, meta, _} ->
          meta[:name] in ["Regex.run", "Regex.scan", "Regex.match?"]

        _ ->
          false
      end)

    cond do
      "parse" in segments ->
        "Parser function"

      has_regex or String.contains?(body_string, ["Regex.run", "Regex.scan", "Regex.match?"]) ->
        "String parsing"

      true ->
        nil
    end
  end

  # Detect numeric algorithms via AST analysis instead of regex on stringified code.
  defp detect_numeric_algorithm(_function_info, meta_ast, _body_string) do
    cond do
      has_math_module_calls?(meta_ast) ->
        "Math module operations"

      has_numeric_kernel_calls?(meta_ast) ->
        "Numeric operations"

      has_significant_arithmetic?(meta_ast) ->
        "Arithmetic operations"

      true ->
        nil
    end
  end

  # --- AST helper functions ---

  @map_write_fns [
    "Map.put",
    "Map.put_new",
    "Map.put_new_lazy",
    "Map.merge",
    "Map.update",
    "Map.update!",
    "Map.delete",
    "Map.drop",
    "Map.take",
    "Map.replace!",
    "Map.split"
  ]

  defp has_struct_manipulation?(meta_ast) do
    Metastatic.postwalker(meta_ast)
    |> Enum.any?(fn
      {:function_call, meta, _} ->
        meta[:name] == "%"

      {:map, _, fields} when is_list(fields) ->
        Enum.any?(fields, fn
          {:pair, _, [{:literal, _, :__struct__}, _]} -> true
          _ -> false
        end)

      _ ->
        false
    end)
  end

  defp has_map_manipulation?(meta_ast) do
    Metastatic.postwalker(meta_ast)
    |> Enum.any?(fn
      {:function_call, meta, _} -> meta[:name] in @map_write_fns
      _ -> false
    end)
  end

  defp has_math_module_calls?(meta_ast) do
    Metastatic.postwalker(meta_ast)
    |> Enum.any?(fn
      {:function_call, meta, _} ->
        name = to_string(meta[:name] || "")
        String.starts_with?(name, "math.") or String.starts_with?(name, ":math.")

      _ ->
        false
    end)
  end

  @numeric_kernel_fns ["div", "rem", "abs", "round", "floor", "ceil", "trunc"]

  defp has_numeric_kernel_calls?(meta_ast) do
    Metastatic.postwalker(meta_ast)
    |> Enum.any?(fn
      {:binary_op, meta, _} -> meta[:operator] in [:div, :rem]
      {:function_call, meta, _} -> meta[:name] in @numeric_kernel_fns
      _ -> false
    end)
  end

  defp has_significant_arithmetic?(meta_ast) do
    count =
      Metastatic.postwalker(meta_ast)
      |> Enum.count(fn
        {:binary_op, meta, [_left, _right]} ->
          meta[:category] == :arithmetic or meta[:operator] in [:+, :-, :*, :/]

        _ ->
          false
      end)

    count >= 2
  end

  defp to_body_string(body) do
    Metastatic.to_string(body)
  rescue
    _ -> Macro.to_string(body)
  end

  # Match function names against inverse pair patterns.
  # For prefix patterns ending in "_" (like "to_"), match as prefix only.
  # For other patterns, match as exact name or exact segment after splitting by "_".
  defp name_matches?(name, pattern) do
    name_str = safe_to_string(name)

    if String.ends_with?(pattern, "_") do
      String.starts_with?(name_str, pattern)
    else
      name_str == pattern or
        name_str
        |> String.split("_")
        |> Enum.any?(&(&1 == pattern))
    end
  end

  defp safe_to_string(anything) do
    if String.Chars.impl_for(anything),
      do: to_string(anything),
      else: ""
  end
end
