defmodule PropWise.Analyzer do
  @moduledoc """
  Main analyzer that combines purity analysis and pattern detection to score functions.
  """

  alias PropWise.{Parser, PatternDetector, PurityAnalyzer}

  @doc """
  Analyzes all functions in a project and returns candidates for property-based testing.
  """
  def analyze_project(path, opts \\ []) do
    min_score = Keyword.get(opts, :min_score, 3)

    functions = Parser.parse_project(path)

    candidates =
      functions
      |> Enum.map(&analyze_function/1)
      |> Enum.filter(fn result -> result.score >= min_score end)
      |> Enum.sort_by(& &1.score, :desc)

    inverse_pairs = PatternDetector.find_inverse_pairs(functions)

    %{
      candidates: candidates,
      inverse_pairs: inverse_pairs,
      total_functions: length(functions),
      candidates_count: length(candidates)
    }
  end

  @doc """
  Analyzes a single function and returns a scored result.
  """
  def analyze_function(function_info) do
    purity = PurityAnalyzer.analyze(function_info)
    patterns = PatternDetector.detect_patterns(function_info)

    score = calculate_score(purity, patterns, function_info)

    %{
      module: function_info.module,
      name: function_info.name,
      arity: function_info.arity,
      file: function_info.file,
      line: function_info.line,
      type: function_info.type,
      purity: purity,
      patterns: patterns,
      score: score,
      suggestions: generate_suggestions(patterns, function_info)
    }
  end

  defp calculate_score({:impure, _}, _patterns, _function_info), do: 0

  defp calculate_score({:pure, _}, patterns, function_info) do
    base_score = 1

    # Add points for detected patterns
    pattern_score = length(patterns) * 2

    # Bonus for having multiple patterns
    multi_pattern_bonus = if length(patterns) >= 2, do: 2, else: 0

    # Bonus for non-trivial functions (more than 3 lines or multiple clauses)
    complexity_bonus = if complex_enough?(function_info), do: 1, else: 0

    # Bonus for public functions
    visibility_bonus = if function_info.type == :public, do: 1, else: 0

    base_score + pattern_score + multi_pattern_bonus + complexity_bonus + visibility_bonus
  end

  defp complex_enough?(function_info) do
    body_string = Macro.to_string(function_info.body)
    line_count = body_string |> String.split("\n") |> length()

    line_count > 3 or has_multiple_clauses?(function_info.body)
  end

  defp has_multiple_clauses?(body) do
    match?({:case, _, _}, body) or match?({:cond, _, _}, body) or match?({:with, _, _}, body)
  end

  defp generate_suggestions(patterns, function_info) do
    func_name = function_info.name
    module_name = function_info.module |> String.split(".") |> List.last()

    Enum.flat_map(patterns, fn {type, _reason} ->
      case type do
        :collection_operation ->
          [
            """
            property "preserves input size" do
              check all list <- list_of(term()) do
                assert length(#{module_name}.#{func_name}(list)) == length(list)
              end
            end
            """,
            """
            property "contains all original elements" do
              check all list <- list_of(term()) do
                result = #{module_name}.#{func_name}(list)
                assert Enum.all?(list, &(&1 in result))
              end
            end
            """
          ]

        :transformation ->
          [
            """
            property "maintains structural invariants" do
              check all input <- term() do
                result = #{module_name}.#{func_name}(input)
                # Add your invariant checks here
                assert valid_structure?(result)
              end
            end
            """,
            """
            property "handles edge cases" do
              check all input <- one_of([constant(nil), constant([]), constant(%{}), term()]) do
                result = #{module_name}.#{func_name}(input)
                assert is_valid_result?(result)
              end
            end
            """
          ]

        :validation ->
          [
            """
            property "consistent validation results" do
              check all input <- term() do
                result1 = #{module_name}.#{func_name}(input)
                result2 = #{module_name}.#{func_name}(input)
                assert result1 == result2
              end
            end
            """,
            """
            property "boolean return type" do
              check all input <- term() do
                result = #{module_name}.#{func_name}(input)
                assert is_boolean(result)
              end
            end
            """
          ]

        :algebraic ->
          [
            """
            property "associativity" do
              check all a <- term(), b <- term(), c <- term() do
                assert #{module_name}.#{func_name}(#{module_name}.#{func_name}(a, b), c) ==
                       #{module_name}.#{func_name}(a, #{module_name}.#{func_name}(b, c))
              end
            end
            """,
            """
            property "commutativity" do
              check all a <- term(), b <- term() do
                assert #{module_name}.#{func_name}(a, b) == #{module_name}.#{func_name}(b, a)
              end
            end
            """,
            """
            property "identity element" do
              check all a <- term() do
                identity = identity_value()
                assert #{module_name}.#{func_name}(a, identity) == a
              end
            end
            """
          ]

        :encoder_decoder ->
          [
            """
            property "encode/decode round-trip" do
              check all data <- term() do
                encoded = #{module_name}.encode(data)
                assert #{module_name}.decode(encoded) == {:ok, data}
              end
            end
            """,
            """
            property "decode handles invalid input" do
              check all invalid <- binary() do
                case #{module_name}.#{func_name}(invalid) do
                  {:ok, _} -> true
                  {:error, _} -> true
                  _ -> false
                end
              end
            end
            """
          ]

        :parser ->
          [
            """
            property "parse returns expected structure" do
              check all input <- string(:alphanumeric) do
                case #{module_name}.#{func_name}(input) do
                  {:ok, result} -> assert valid_parsed_structure?(result)
                  {:error, _} -> true
                end
              end
            end
            """,
            """
            property "parse/format round-trip" do
              check all data <- valid_data_generator() do
                formatted = #{module_name}.format(data)
                assert #{module_name}.#{func_name}(formatted) == {:ok, data}
              end
            end
            """
          ]

        :numeric ->
          [
            """
            property "handles numeric boundaries" do
              check all n <- one_of([integer(), float()]) do
                result = #{module_name}.#{func_name}(n)
                assert is_number(result)
              end
            end
            """,
            """
            property "handles special numeric values" do
              check all n <- member_of([0, -1, 1, :math.pi(), -:math.pi()]) do
                result = #{module_name}.#{func_name}(n)
                assert is_valid_numeric?(result)
              end
            end
            """
          ]

        _ ->
          []
      end
    end)
    |> Enum.uniq()
  end
end
