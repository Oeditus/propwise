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

  Renders the Markdown report as ANSI-coloured terminal output when format is
  `:text` (default), using a small built-in renderer that covers the subset of
  Markdown this module emits. Outputs raw Markdown when format is `:markdown`.
  Outputs JSON when format is `:json`.

  Set `:color` to `false` (or the `NO_COLOR` env var) to disable ANSI escapes.
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
        IO.puts(render_terminal(markdown, Keyword.get(opts, :color, color_enabled?())))
    end
  end

  defp color_enabled? do
    System.get_env("NO_COLOR") in [nil, ""] and match?({:unix, _}, :os.type())
  end

  # --- Minimal Markdown -> ANSI renderer -------------------------------------
  #
  # Covers exactly the constructs `format_markdown_report/2` produces: ATX
  # headings, bullet lists, fenced code blocks, inline code, bold, and italic.
  # Deliberately dependency-free: an ANSI renderer is not worth a Rust NIF.

  @ansi_reset "\e[0m"
  @ansi_h1 "\e[1;33m"
  @ansi_h2 "\e[1;36m"
  @ansi_h3 "\e[1;37m"
  @ansi_bold "\e[1m"
  @ansi_italic "\e[3m"
  @ansi_code "\e[36m"
  @ansi_bullet "\e[33m\u25B8\e[0m"
  @ansi_dim "\e[2m"

  defp render_terminal(markdown, false), do: markdown

  defp render_terminal(markdown, true) do
    markdown
    |> String.split("\n")
    |> render_lines(false)
    |> Enum.join("\n")
  end

  # `in_fence` tracks whether we are inside a ```elixir block.
  defp render_lines(lines, in_fence), do: do_render_lines(lines, in_fence, [])

  defp do_render_lines([], _in_fence, acc), do: Enum.reverse(acc)

  defp do_render_lines([line | rest], in_fence, acc) do
    cond do
      String.starts_with?(line, "```") ->
        do_render_lines(rest, not in_fence, [@ansi_dim <> line <> @ansi_reset | acc])

      in_fence ->
        do_render_lines(rest, in_fence, [@ansi_code <> line <> @ansi_reset | acc])

      true ->
        do_render_lines(rest, in_fence, [render_line(line) | acc])
    end
  end

  defp render_line("# " <> title), do: @ansi_h1 <> title <> @ansi_reset
  defp render_line("## " <> title), do: @ansi_h2 <> title <> @ansi_reset
  defp render_line("### " <> title), do: @ansi_h3 <> title <> @ansi_reset

  defp render_line("- " <> item), do: "  " <> @ansi_bullet <> " " <> inline(item)

  defp render_line("  - " <> item), do: "    " <> @ansi_bullet <> " " <> inline(item)

  defp render_line(line), do: inline(line)

  # Inline spans: `code`, **bold**, _italic_.
  defp inline(text) do
    text
    |> then(&Regex.replace(~r/`([^`]+)`/, &1, @ansi_code <> "\\1" <> @ansi_reset))
    |> then(&Regex.replace(~r/\*\*([^*]+)\*\*/, &1, @ansi_bold <> "\\1" <> @ansi_reset))
    |> then(&Regex.replace(~r/(?<!\w)_([^_]+)_(?!\w)/, &1, @ansi_italic <> "\\1" <> @ansi_reset))
  end

  @default_display_limit 3

  defp format_markdown_report(
         %{
           candidates: candidates,
           inverse_pairs: inverse_pairs,
           total_functions: total,
           candidates_count: count,
           dropped_count: dropped
         } = result,
         opts
       ) do
    library = Keyword.get(opts, :library, :stream_data)
    show_all = Keyword.get(opts, :show_all, false)
    limit = if show_all, do: :infinity, else: Keyword.get(opts, :limit, @default_display_limit)
    baseline = Keyword.get(opts, :baseline)

    summary_lines = [
      "# PropWise Analysis Report\n",
      "## Summary",
      "- **Total functions analyzed:** #{total}",
      "- **Property test candidates:** #{count}",
      "- **Candidates dropped (below threshold):** #{dropped}"
    ]

    summary_lines =
      if count > 0 and total > 0 do
        percentage = Float.round(count / total * 100, 1)
        # credo:disable-for-next-line Credo.Check.Refactor.AppendSingleItem
        summary_lines ++ ["- **Coverage:** #{percentage}%"]
      else
        summary_lines
      end

    summary_lines = summary_lines ++ purity_lines(result)

    summary_lines =
      if total == 0 do
        [
          "- **Warning:** no `.ex` files found. Check `analyze_paths` in `.propwise.exs` " <>
            "or pass a valid path."
          | summary_lines
        ]
        |> Enum.reverse()
      else
        summary_lines
      end

    summary_lines = summary_lines ++ baseline_lines(baseline)

    pairs_section = format_pairs_section(inverse_pairs, limit)

    candidates_section =
      if Enum.empty?(candidates) do
        empty_section(baseline)
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

  defp empty_section(nil) do
    ["\nNo strong candidates found. Consider lowering the min_score threshold."]
  end

  defp empty_section(_baseline) do
    ["\nNo new candidates since the baseline. Nothing to do."]
  end

  # Purity breakdown, when the analyzer supplied it.
  defp purity_lines(%{purity_counts: %{pure: pure, unknown: unknown, impure: impure}}) do
    [
      "- **Purity:** #{pure} pure, #{unknown} unknown, #{impure} impure"
    ]
  end

  defp purity_lines(_result), do: []

  defp baseline_lines(nil), do: []

  defp baseline_lines(baseline) do
    ["- **Baseline:** #{baseline.path} (#{baseline.size} accepted candidate(s))"]
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
      "- **Purity:** #{format_purity(candidate)}",
      "- **Location:** #{relative_path(candidate.file)}:#{candidate.line}",
      "- **Type:** #{candidate.type}"
    ]

    lines = lines ++ unresolved_lines(candidate)

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
      if Enum.empty?(Map.get(candidate, :laws, [])) do
        lines
      else
        law_line = Enum.map_join(candidate.laws, ", ", &format_law/1)
        Enum.concat(lines, ["- **Inferred laws:** #{law_line}"])
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

  defp format_purity(%{purity: :pure}), do: "pure"
  defp format_purity(%{purity: :unknown}), do: "unknown (unresolved calls)"
  defp format_purity(%{purity: :impure}), do: "impure"
  defp format_purity(_candidate), do: "n/a"

  # For `:unknown` functions, show *what* could not be resolved — this is the
  # difference between a useful report and a shrug.
  defp unresolved_lines(%{purity: :unknown, unresolved_calls: calls}) when calls != [] do
    shown = calls |> Enum.take(3) |> Enum.join(", ")
    suffix = if length(calls) > 3, do: ", …", else: ""
    ["- **Unresolved calls:** #{shown}#{suffix}"]
  end

  defp unresolved_lines(_candidate), do: []

  defp format_law(:involution), do: "involution"
  defp format_law(:idempotent), do: "idempotence"
  defp format_law(:associative), do: "associativity"
  defp format_law(:commutative), do: "commutativity"
  defp format_law(:identity), do: "identity element"
  defp format_law(:permutation), do: "permutation"
  defp format_law(:length_preserving), do: "length preservation"
  defp format_law(:monotonic), do: "monotonicity"
  defp format_law(:round_trip), do: "round-trip"
  defp format_law(:total), do: "totality"
  defp format_law(:bounded), do: "bounded output"
  defp format_law(:deterministic), do: "determinism"
  defp format_law(other), do: to_string(other)

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
      purity: Map.get(candidate, :purity),
      side_effects: Enum.map(Map.get(candidate, :side_effects, []), &serialize_side_effect/1),
      unresolved_calls: Map.get(candidate, :unresolved_calls, []),
      score: candidate.score,
      rank: candidate.rank,
      inverse_pair: Map.get(candidate, :inverse_pair, false),
      patterns:
        Enum.map(candidate.patterns, fn {type, reason} -> %{type: type, reason: reason} end),
      laws: Map.get(candidate, :laws, []),
      suggestions: candidate.suggestions
    }
  end

  # Side effects are tuples internally; JSON needs plain maps.
  defp serialize_side_effect({:semantic_op, domain, operation}) do
    %{type: "semantic_op", domain: to_string(domain), operation: to_string(operation)}
  end

  defp serialize_side_effect({:module_call, module, function, arity}) do
    %{
      type: "module_call",
      module: inspect(module),
      function: to_string(function),
      arity: arity
    }
  end

  defp serialize_side_effect({:function_call, function, arity}) do
    %{type: "function_call", function: to_string(function), arity: arity}
  end

  defp serialize_side_effect({:receive_block}), do: %{type: "receive_block"}

  defp serialize_side_effect(other), do: %{type: "unknown", value: inspect(other)}

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
  defp format_rank(%{rank: rank}) when is_integer(rank), do: "#{rank}. "
  defp format_rank(_candidate), do: ""

  defp format_rank_number(%{rank: rank}) when is_integer(rank), do: "##{rank}"
  defp format_rank_number(_candidate), do: "n/a"

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
