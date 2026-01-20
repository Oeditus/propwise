defmodule PropWise.Analyzer do
  @moduledoc """
  Main analyzer that combines purity analysis and pattern detection to score functions.
  """

  alias PropWise.{Config, Parser, PatternDetector, PurityAnalyzer, SuggestionGenerator}

  @doc """
  Analyzes all functions in a project and returns candidates for property-based testing.
  """
  def analyze_project(path, opts \\ []) do
    min_score = Keyword.get(opts, :min_score, 4)
    library = Keyword.get(opts, :library) || Config.library(path)

    functions = Parser.parse_project(path)

    all_scored_candidates =
      functions
      |> Enum.map(&analyze_function(&1, library))

    candidates =
      all_scored_candidates
      |> Enum.filter(fn result -> result.score >= min_score end)
      |> Enum.sort_by(& &1.score, :desc)

    dropped_count =
      all_scored_candidates
      |> Enum.count(fn result -> result.score > 0 and result.score < min_score end)

    inverse_pairs = PatternDetector.find_inverse_pairs(functions)

    %{
      candidates: candidates,
      inverse_pairs: inverse_pairs,
      total_functions: length(functions),
      candidates_count: length(candidates),
      dropped_count: dropped_count
    }
  end

  @doc """
  Analyzes a single function and returns a scored result.
  """
  def analyze_function(function_info, library \\ :stream_data) do
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
      suggestions: generate_suggestions(patterns, function_info, library)
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

  defp generate_suggestions(patterns, function_info, library) do
    SuggestionGenerator.generate(patterns, function_info, library)
  end
end
