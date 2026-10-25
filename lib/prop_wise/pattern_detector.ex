defmodule PropWise.PatternDetector do
  @moduledoc """
  Detects patterns in function MetaASTs that indicate good property-based testing candidates.
  """

  @inverse_name_pairs [
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

  alias PropWise.PurityAnalyzer

  @doc """
  Analyzes a function and returns detected patterns that suggest property-based testing.
  """
  @spec detect_patterns(PropWise.FunctionInfo.t() | map()) :: [PropWise.Candidate.pattern()]
  def detect_patterns(function_info) do
    ctx = build_ctx(function_info)

    for {type, detector} <- detectors(),
        reason = detector.(ctx),
        reason != nil do
      {type, reason}
    end
  end

  # Detector registry: adding a new pattern is a one-line change here.
  # Local anonymous captures (not `apply/3`) so private functions are reachable.
  defp detectors do
    [
      collection_operation: &detect_collection_operation/1,
      transformation: &detect_transformation/1,
      validation: &detect_validation/1,
      algebraic: &detect_algebraic_structure/1,
      encoder_decoder: &detect_encoder_decoder/1,
      parser: &detect_parser/1,
      numeric: &detect_numeric_algorithm/1
    ]
  end

  defp build_ctx(function_info) do
    meta_ast = PurityAnalyzer.ensure_meta_ast(function_info.body)

    %{
      info: function_info,
      meta_ast: meta_ast,
      # Lazily computed on first use: stringifying every body eagerly is the hot
      # path on large codebases and most detectors never need it.
      body_string: nil
    }
  end

  defp body_string(%{body_string: nil} = ctx) do
    to_body_string(ctx.meta_ast)
  end

  defp body_string(%{body_string: string}), do: string

  @doc """
  Finds pairs of functions that appear to be inverses of each other.

  Uses an index keyed on `{module, name}` so the search is O(n) rather than
  O(n² · |patterns|). Cross-module pairs are *not* reported; only functions
  defined in the same module are considered inverses.
  """
  @spec find_inverse_pairs([PropWise.FunctionInfo.t() | map()]) :: [map()]
  def find_inverse_pairs(functions) do
    index =
      Enum.reduce(functions, %{}, fn f, acc ->
        Map.update(acc, {f.module, safe_to_string(f.name)}, [f], &[f | &1])
      end)

    for {forward, inverse} <- @inverse_name_pairs,
        f1 <- functions,
        f2 <- lookup(index, f1.module, inverse_name(f1.name, forward, inverse)),
        f1.name != f2.name,
        name_matches?(f1.name, forward) do
      %{
        type: :inverse_pair,
        forward: {f1.module, f1.name, f1.arity},
        inverse: {f2.module, f2.name, f2.arity},
        suggestion: "Test round-trip property: #{f2.name}(#{f1.name}(x)) == x"
      }
    end
    |> Enum.uniq_by(fn pair -> {pair.forward, pair.inverse} end)
  end

  defp lookup(index, module, name), do: Map.get(index, {module, name}, [])

  # Produce the candidate inverse name for a function name and a pattern pair.
  # Prefix patterns ("to_" / "from_") swap the prefix; segment patterns swap the
  # matching `_`-separated segment.
  defp inverse_name(name, forward, inverse) do
    name_str = safe_to_string(name)

    if String.ends_with?(forward, "_") or String.ends_with?(inverse, "_") do
      source = String.trim_trailing(forward, "_")
      target = String.trim_trailing(inverse, "_")

      cond do
        String.starts_with?(name_str, forward) ->
          target <> "_" <> String.replace_prefix(name_str, forward, "")

        String.starts_with?(name_str, inverse) ->
          source <> "_" <> String.replace_prefix(name_str, inverse, "")

        true ->
          name_str
      end
    else
      segments = String.split(name_str, "_")

      Enum.map_join(segments, "_", fn
        ^forward -> inverse
        ^inverse -> forward
        other -> other
      end)
    end
  end

  # Detect collection operations (map, filter, sort, group)
  defp detect_collection_operation(%{meta_ast: meta_ast} = ctx) do
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

    if has_collection_node do
      "Uses Enum collection operations"
    else
      patterns = [
        {~r/Enum\.(map|filter|sort|group|reduce|flat_map|chunk)/,
         "Uses Enum collection operations"},
        {~r/Stream\.(map|filter|chunk|take|drop)/, "Uses Stream operations"},
        {~r/\|> Enum\./, "Pipeline with Enum operations"},
        {~r/for .+ <- .+/, "List comprehension"}
      ]

      Enum.find_value(patterns, fn {regex, reason} ->
        if Regex.match?(regex, body_string(ctx)), do: reason
      end)
    end
  end

  # Detect data transformations via struct/map manipulation.
  # Deliberately excludes bare pipelines and `with` blocks which are too common.
  defp detect_transformation(%{meta_ast: meta_ast}) do
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
  defp detect_validation(%{info: function_info}) do
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
  defp detect_algebraic_structure(%{info: function_info}) do
    name = safe_to_string(function_info.name)
    segments = String.split(name, "_")

    algebraic_operations = ~w[merge concat combine union intersect compose append]

    if Enum.any?(algebraic_operations, fn op -> op in segments end) do
      "Potentially algebraic operation"
    end
  end

  # Detect encoder/decoder functions
  defp detect_encoder_decoder(%{info: function_info}) do
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

  # Detect parser functions.
  #
  # `Regex.match?/2` is deliberately excluded: it is a predicate, not a parser.
  # A `?`-suffixed function is a validation concern, never a parser, so we bail
  # out early for those to avoid double-labelling predicates as parsers.
  defp detect_parser(%{info: function_info, meta_ast: meta_ast} = ctx) do
    name = safe_to_string(function_info.name)
    segments = String.split(name, "_")

    if String.ends_with?(name, "?") do
      nil
    else
      has_regex =
        Metastatic.postwalker(meta_ast)
        |> Enum.any?(fn
          {:function_call, meta, _} ->
            meta[:name] in ["Regex.run", "Regex.scan"]

          _ ->
            false
        end)

      cond do
        "parse" in segments ->
          "Parser function"

        has_regex or String.contains?(body_string(ctx), ["Regex.run", "Regex.scan"]) ->
          "String parsing"

        true ->
          nil
      end
    end
  end

  # Detect numeric algorithms via AST analysis instead of regex on stringified code.
  defp detect_numeric_algorithm(%{meta_ast: meta_ast}) do
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
