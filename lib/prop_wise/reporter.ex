defmodule PropWise.Reporter do
  @moduledoc """
  Formats and outputs analysis results.
  """

  @doc """
  Prints analysis results in a human-readable format.
  """
  def print_report(analysis_result, opts \\ []) do
    format = Keyword.get(opts, :format, :text)

    case format do
      :text -> print_text_report(analysis_result)
      :json -> print_json_report(analysis_result)
      _ -> print_text_report(analysis_result)
    end
  end

  defp print_text_report(%{
         candidates: candidates,
         inverse_pairs: inverse_pairs,
         total_functions: total,
         candidates_count: count
       }) do
    IO.puts("\n" <> String.duplicate("=", 80))
    IO.puts("PropWise Analysis Report")
    IO.puts(String.duplicate("=", 80))

    IO.puts("\nSummary:")
    IO.puts("  Total functions analyzed: #{total}")
    IO.puts("  Property test candidates: #{count}")

    if count > 0 do
      percentage = Float.round(count / total * 100, 1)
      IO.puts("  Coverage: #{percentage}%")
    end

    if not Enum.empty?(inverse_pairs) do
      IO.puts("\n" <> String.duplicate("-", 80))
      IO.puts("Inverse Function Pairs Detected:")
      IO.puts(String.duplicate("-", 80))

      for pair <- inverse_pairs do
        {mod, name1, arity1} = pair.forward
        {_mod, name2, arity2} = pair.inverse
        IO.puts("\n  #{mod}.#{name1}/#{arity1} <-> #{name2}/#{arity2}")
        IO.puts("  Suggestion: #{pair.suggestion}")
      end
    end

    if Enum.empty?(candidates) do
      IO.puts("\nNo strong candidates found. Consider lowering the min_score threshold.")
    else
      IO.puts("\n" <> String.duplicate("-", 80))
      IO.puts("Top Candidates (sorted by score):")
      IO.puts(String.duplicate("-", 80))

      candidates
      |> Enum.take(20)
      |> Enum.each(&print_candidate/1)
    end

    IO.puts("\n" <> String.duplicate("=", 80))
    IO.puts("")
  end

  defp print_candidate(candidate) do
    IO.puts("\n#{candidate.module}.#{candidate.name}/#{candidate.arity}")
    IO.puts("  Score: #{candidate.score}")
    IO.puts("  Location: #{relative_path(candidate.file)}:#{candidate.line}")
    IO.puts("  Type: #{candidate.type}")

    if not Enum.empty?(candidate.patterns) do
      IO.puts("  Patterns:")

      for {type, reason} <- candidate.patterns do
        IO.puts("    - #{format_pattern(type)}: #{reason}")
      end
    end

    if not Enum.empty?(candidate.suggestions) do
      IO.puts("  Testing suggestions:")

      for suggestion <- candidate.suggestions do
        IO.puts("    - #{suggestion}")
      end
    end
  end

  defp print_json_report(analysis_result) do
    json =
      analysis_result
      |> Map.update!(:candidates, fn candidates ->
        Enum.map(candidates, &serialize_candidate/1)
      end)
      |> Jason.encode!(pretty: true)

    IO.puts(json)
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
