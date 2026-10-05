defmodule PropWise.Reporter do
  @moduledoc """
  Formats and outputs analysis results.
  """

  @doc """
  Formats analysis results and returns as a string.
  Formats: `:text` / `:markdown` (default) or `:json`.
  """
  @spec format_report(PropWise.Analyzer.analysis_result(), keyword()) :: String.t()
  def format_report(analysis_result, opts \\ []) do
    format = Keyword.get(opts, :format, :text)

    case format do
      f when f in [:markdown, :text, "text", "markdown"] ->
        format_markdown_report(analysis_result, opts)

      f when f in [:json, "json"] ->
        format_json_report(analysis_result)

      _ ->
        format_markdown_report(analysis_result, opts)
    end
  end

  @doc """
  Prints analysis results.
  Renders Markdown with Marcli for terminal output when format is `:text` (default).
  Outputs raw Markdown when format is `:markdown`.
  Outputs JSON when format is `:json`.
  """
  @spec print_report(PropWise.Analyzer.analysis_result(), keyword()) :: :ok
  def print_report(analysis_result, opts \\ []) do
    format = Keyword.get(opts, :format, :text)

    case format do
      f when f in [:json, "json"] ->
        IO.puts(format_json_report(analysis_result))

      f when f in [:markdown, "markdown"] ->
        IO.puts(format_markdown_report(analysis_result, opts))

      _ ->
        markdown = format_markdown_report(analysis_result, opts)

        try do
          IO.puts(Marcli.render(markdown))
        rescue
          _ -> IO.puts(markdown)
        catch
          _, _ -> IO.puts(markdown)
        end
    end
  end

  @default_display_limit 3

  defp format_markdown_report(
         %{
           candidates: candidates,
           inverse_pairs: inverse_pairs,
           total_functions: total,
           candidates_count: count,
           dropped_count: dropped
         },
         opts
       ) do
    library = Keyword.get(opts, :library, :stream_data)
    show_all = Keyword.get(opts, :show_all, false)
    limit = if show_all, do: :infinity, else: Keyword.get(opts, :limit, @default_display_limit)

    summary_lines = [
      "# PropWise Analysis Report\n",
      "## Summary",
      "- **Total functions analyzed:** #{total}",
      "- **Property test candidates:** #{count}",
      "- **Candidates dropped (below threshold):** #{dropped}"
    ]

    summary_lines =
      if count > 0 do
        percentage = Float.round(count / total * 100, 1)
        # credo:disable-for-next-line Credo.Check.Refactor.AppendSingleItem
        summary_lines ++ ["- **Coverage:** #{percentage}%"]
      else
        summary_lines
      end

    pairs_section = format_pairs_section(inverse_pairs, limit)

    candidates_section =
      if Enum.empty?(candidates) do
        ["\nNo strong candidates found. Consider lowering the min_score threshold."]
      else
        shown = take_limit(candidates, limit)
        hidden = length(candidates) - length(shown)

        candidate_blocks =
          Enum.map(shown, &format_candidate_markdown(&1, library))

        more_line =
          if hidden > 0 do
            ["\n_… and #{hidden} more (run with `--show-all` to see all findings)._"]
          else
            []
          end

        ["\n## Candidates (ranked)\n" | candidate_blocks ++ more_line]
      end

    (summary_lines ++ pairs_section ++ candidates_section)
    |> Enum.join("\n")
  end

  defp format_pairs_section(inverse_pairs, limit) do
    if Enum.empty?(inverse_pairs) do
      []
    else
      shown = take_limit(inverse_pairs, limit)
      hidden = length(inverse_pairs) - length(shown)

      pair_lines =
        for {pair, index} <- Enum.with_index(shown, 1) do
          {mod, name1, arity1} = pair.forward
          {_mod, name2, arity2} = pair.inverse

          "#{index}. `#{mod}.#{name1}/#{arity1}` <-> `#{name2}/#{arity2}`\n  - **Suggestion:** #{pair.suggestion}"
        end

      more_line =
        if hidden > 0 do
          ["\n_… and #{hidden} more inverse pairs (run with `--show-all` to see all)._"]
        else
          []
        end

      ["\n## Inverse Function Pairs Detected\n" | pair_lines ++ more_line]
    end
  end

  defp take_limit(list, :infinity), do: list
  defp take_limit(list, limit) when is_integer(limit), do: Enum.take(list, limit)

  defp format_candidate_markdown(candidate, library) do
    lines = [
      "### #{format_rank(candidate)}#{candidate.module}.#{candidate.name}/#{candidate.arity}",
      "- **Rank:** #{format_rank_number(candidate)}",
      "- **Score:** #{candidate.score}",
      "- **Location:** #{relative_path(candidate.file)}:#{candidate.line}",
      "- **Type:** #{candidate.type}"
    ]

    lines =
      if Enum.empty?(candidate.patterns) do
        lines
      else
        pattern_lines =
          for {type, reason} <- candidate.patterns do
            "  - #{format_pattern(type)}: #{reason}"
          end

        Enum.concat([lines, ["- **Patterns:**"], pattern_lines])
      end

    lines =
      if Enum.empty?(candidate.suggestions) do
        lines
      else
        suggestions_code =
          Enum.map_join(candidate.suggestions, "\n\n", &format_code_snippet/1)

        code_block = "```elixir\n# #{library} example\n#{suggestions_code}\n```"
        Enum.concat(lines, ["- **Testing suggestions:**", code_block])
      end

    Enum.join(lines, "\n") <> "\n"
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
      rank: Map.get(candidate, :rank),
      inverse_pair: Map.get(candidate, :inverse_pair, false),
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

  # Heading prefix, e.g. "1. " so the rank is visible at a glance.
  defp format_rank(candidate) do
    case Map.get(candidate, :rank) do
      nil -> ""
      rank -> "#{rank}. "
    end
  end

  defp format_rank_number(candidate) do
    case Map.get(candidate, :rank) do
      nil -> "n/a"
      rank -> "##{rank}"
    end
  end

  defp relative_path(path) do
    cwd = File.cwd!()

    if String.starts_with?(path, cwd) do
      String.replace_prefix(path, cwd <> "/", "")
    else
      path
    end
  end

  defp format_code_snippet(snippet) do
    snippet
    |> Code.format_string!()
    |> IO.iodata_to_binary()
  rescue
    _ -> String.trim(snippet)
  end
end
