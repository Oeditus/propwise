defmodule PropWise.Reporter do
  @moduledoc """
  Formats and outputs analysis results.
  """

  @doc """
  Formats analysis results and returns as a string.
  """
  def format_report(analysis_result, opts \\ []) do
    format = Keyword.get(opts, :format, :text)

    case format do
      :text -> format_text_report(analysis_result)
      :json -> format_json_report(analysis_result)
      _ -> format_text_report(analysis_result)
    end
  end

  @doc """
  Prints analysis results in a human-readable format.
  """
  def print_report(analysis_result, opts \\ []) do
    analysis_result
    |> format_report(opts)
    |> IO.puts()
  end

  defp format_text_report(%{
         candidates: candidates,
         inverse_pairs: inverse_pairs,
         total_functions: total,
         candidates_count: count,
         dropped_count: dropped
       }) do
    lines = [
      "\n" <> String.duplicate("=", 80),
      "PropWise Analysis Report",
      String.duplicate("=", 80),
      "\nSummary:",
      "  Total functions analyzed: #{total}",
      "  Property test candidates: #{count}",
      "  Candidates dropped (below threshold): #{dropped}"
    ]

    lines =
      if count > 0 do
        percentage = Float.round(count / total * 100, 1)
        lines ++ ["  Coverage: #{percentage}%"]
      else
        lines
      end

    lines =
      if not Enum.empty?(inverse_pairs) do
        pair_lines =
          for pair <- inverse_pairs do
            {mod, name1, arity1} = pair.forward
            {_mod, name2, arity2} = pair.inverse

            [
              "\n  #{mod}.#{name1}/#{arity1} <-> #{name2}/#{arity2}",
              "  Suggestion: #{pair.suggestion}"
            ]
          end
          |> List.flatten()

        lines ++
          [
            "\n" <> String.duplicate("-", 80),
            "Inverse Function Pairs Detected:",
            String.duplicate("-", 80)
          ] ++ pair_lines
      else
        lines
      end

    lines =
      if Enum.empty?(candidates) do
        lines ++ ["\nNo strong candidates found. Consider lowering the min_score threshold."]
      else
        candidate_lines =
          candidates
          |> Enum.take(20)
          |> Enum.flat_map(&format_candidate/1)

        lines ++
          [
            "\n" <> String.duplicate("-", 80),
            "Top Candidates (sorted by score):",
            String.duplicate("-", 80)
          ] ++ candidate_lines
      end

    lines = lines ++ ["\n" <> String.duplicate("=", 80), ""]
    Enum.join(lines, "\n")
  end

  defp format_candidate(candidate) do
    lines = [
      "\n#{candidate.module}.#{candidate.name}/#{candidate.arity}",
      "  Score: #{candidate.score}",
      "  Location: #{relative_path(candidate.file)}:#{candidate.line}",
      "  Type: #{candidate.type}"
    ]

    lines =
      if not Enum.empty?(candidate.patterns) do
        pattern_lines =
          for {type, reason} <- candidate.patterns do
            "    - #{format_pattern(type)}: #{reason}"
          end

        lines ++ ["  Patterns:"] ++ pattern_lines
      else
        lines
      end

    if not Enum.empty?(candidate.suggestions) do
      suggestion_lines =
        for suggestion <- candidate.suggestions do
          "    - #{suggestion}"
        end

      lines ++ ["  Testing suggestions:"] ++ suggestion_lines
    else
      lines
    end
  end

  defp format_json_report(analysis_result) do
    analysis_result
    |> Map.update!(:candidates, fn candidates ->
      Enum.map(candidates, &serialize_candidate/1)
    end)
    |> Map.update!(:inverse_pairs, fn pairs ->
      Enum.map(pairs, &serialize_inverse_pair/1)
    end)
    |> Jason.encode!(pretty: true)
  end

  defp serialize_candidate(candidate) do
    %{
      module: candidate.module,
      name: to_string(candidate.name),
      arity: candidate.arity,
      file: candidate.file,
      line: candidate.line,
      type: candidate.type,
      score: candidate.score,
      patterns:
        Enum.map(candidate.patterns, fn {type, reason} -> %{type: type, reason: reason} end),
      suggestions: candidate.suggestions
    }
  end

  defp serialize_inverse_pair(pair) do
    {mod1, name1, arity1} = pair.forward
    {mod2, name2, arity2} = pair.inverse

    %{
      forward: %{
        module: mod1,
        name: to_string(name1),
        arity: arity1
      },
      inverse: %{
        module: mod2,
        name: to_string(name2),
        arity: arity2
      },
      suggestion: pair.suggestion
    }
  end

  defp format_pattern(:collection_operation), do: "Collection Operation"
  defp format_pattern(:transformation), do: "Data Transformation"
  defp format_pattern(:validation), do: "Validation"
  defp format_pattern(:algebraic), do: "Algebraic Structure"
  defp format_pattern(:encoder_decoder), do: "Encoder/Decoder"
  defp format_pattern(:parser), do: "Parser"
  defp format_pattern(:numeric), do: "Numeric Algorithm"
  defp format_pattern(other), do: to_string(other)

  defp relative_path(path) do
    cwd = File.cwd!()

    if String.starts_with?(path, cwd) do
      String.replace_prefix(path, cwd <> "/", "")
    else
      path
    end
  end
end
