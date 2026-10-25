defmodule PropWise.Analyzer do
  @moduledoc """
  Main analyzer that combines purity analysis, pattern detection and law
  inference to score functions.

  ## Scoring

  See `stuff/docs/SCORING.md` for the full rules. In short:

    * impure functions score 0 and are never reported
    * `:pure` functions score in full
    * `:unknown` functions score at `@unknown_weight` (default 0.5) of the
      equivalent pure function, rounded down — they are still worth looking at,
      but genuinely clean functions rank first
  """

  alias PropWise.{
    Candidate,
    Config,
    FunctionInfo,
    LawTable,
    Parser,
    PatternDetector,
    PurityAnalyzer,
    SuggestionGenerator
  }

  @complexity_node_threshold 12

  # Score multiplier applied to `:unknown`-purity functions.
  #
  # Half weight: an `:unknown` function with the same evidence as a `:pure` one
  # is still reported (if it clears the threshold) but sorts below it.
  @unknown_weight 0.5

  @type analysis_result :: %{
          candidates: [Candidate.t()],
          inverse_pairs: [map()],
          total_functions: non_neg_integer(),
          candidates_count: non_neg_integer(),
          dropped_count: non_neg_integer(),
          purity_counts: %{
            pure: non_neg_integer(),
            unknown: non_neg_integer(),
            impure: non_neg_integer()
          }
        }

  @doc """
  Analyzes all functions in a project and returns candidates for property-based testing.
  """
  @spec analyze_project(String.t(), keyword()) :: analysis_result()
  def analyze_project(path, opts \\ []) do
    Application.ensure_all_started(:metastatic)

    if Code.ensure_loaded?(Metastatic.Application) do
      Metastatic.Application.start(:normal, [])
    end

    # Load config once and thread through to avoid double Code.eval_file
    on_config_error = Keyword.get(opts, :on_config_error)
    config = Config.load(path, on_error: on_config_error)
    min_score = Keyword.get(opts, :min_score, 4)
    library = Keyword.get(opts, :library) || Map.get(config, :library, :stream_data)
    analyze_paths = Map.get(config, :analyze_paths, ["lib"])
    purity_opts = purity_opts(config, opts)
    parser_opts = Keyword.put_new(opts, :analyze_paths, analyze_paths)
    functions = Parser.parse_project(path, parser_opts)

    all_scored_candidates =
      Enum.map(functions, &analyze_function(&1, library, purity_opts))

    candidates =
      Enum.filter(all_scored_candidates, fn result -> result.score >= min_score end)

    dropped_count =
      Enum.count(all_scored_candidates, fn result ->
        result.score > 0 and result.score < min_score
      end)

    inverse_pairs = PatternDetector.find_inverse_pairs(functions)

    candidates =
      candidates
      |> mark_inverse_pair_members(inverse_pairs)
      |> rank_candidates()

    %{
      candidates: candidates,
      inverse_pairs: inverse_pairs,
      total_functions: length(functions),
      candidates_count: length(candidates),
      dropped_count: dropped_count,
      purity_counts: count_purities(all_scored_candidates)
    }
  end

  @doc """
  Analyzes a single function and returns a scored result.

  `purity_opts` is forwarded to `PropWise.PurityAnalyzer.analyze/2` (e.g.
  `:pure_modules`).
  """
  @spec analyze_function(FunctionInfo.t() | map(), atom(), keyword()) :: Candidate.t()
  def analyze_function(function_info, library \\ :stream_data, purity_opts \\ []) do
    purity_result = PurityAnalyzer.analyze(function_info, purity_opts)
    patterns = PatternDetector.detect_patterns(function_info)
    laws = infer_laws(function_info, meta_ast(function_info), patterns)

    score = calculate_score(purity_result, patterns, function_info)

    %Candidate{
      module: function_info.module,
      name: function_info.name,
      arity: function_info.arity,
      file: function_info.file,
      line: function_info.line,
      type: function_info.type,
      purity: purity_result.purity,
      side_effects: purity_result.side_effects,
      unresolved_calls: purity_result.unresolved_calls,
      patterns: patterns,
      laws: laws,
      score: score,
      # A single-function analysis is trivially ranked #1; project-wide analysis
      # overwrites this in `rank_candidates/1`.
      rank: 1,
      suggestions: generate_suggestions(patterns, function_info, library, laws)
    }
  end

  # ----- Law inference --------------------------------------------------------

  # Collects the call names in a body and asks the law table what they imply.
  # Pattern-derived laws are merged in so that, e.g., an `:algebraic` pattern
  # always contributes associativity even if the callee is unknown.
  defp infer_laws(_function_info, meta_ast, patterns) do
    call_laws =
      meta_ast
      |> call_names()
      |> LawTable.laws_for_calls()

    pattern_laws =
      patterns
      |> Enum.flat_map(&laws_for_pattern/1)

    (call_laws ++ pattern_laws)
    |> Enum.uniq()
    |> Enum.reject(&(&1 == :deterministic and call_laws ++ pattern_laws != [:deterministic]))
  end

  defp laws_for_pattern({:algebraic, _}), do: [:associative, :commutative, :identity]
  defp laws_for_pattern({:encoder_decoder, _}), do: [:round_trip]
  defp laws_for_pattern({:parser, _}), do: [:round_trip]
  defp laws_for_pattern({:validation, _}), do: [:total]
  defp laws_for_pattern({:numeric, _}), do: [:total]
  defp laws_for_pattern(_), do: []

  defp call_names(meta_ast) do
    meta_ast
    |> Metastatic.postwalker()
    |> Enum.flat_map(fn
      {:function_call, meta, _} -> [to_string(meta[:name] || "")]
      _ -> []
    end)
  rescue
    _ -> []
  end

  defp meta_ast(function_info) do
    PurityAnalyzer.ensure_meta_ast(function_info.body)
  rescue
    _ -> {:block, [], []}
  end

  # ----- Scoring --------------------------------------------------------------

  defp calculate_score(%{purity: :impure}, _patterns, _function_info), do: 0

  defp calculate_score(%{purity: purity}, patterns, function_info) do
    base_score = 1

    # Add points for detected patterns
    pattern_score = length(patterns) * 2

    # Bonus for having multiple patterns
    multi_pattern_bonus = if length(patterns) >= 2, do: 2, else: 0

    # Bonus for non-trivial functions
    complexity_bonus = if complex_enough?(function_info), do: 1, else: 0

    # Bonus for public functions
    visibility_bonus = if function_info.type == :public, do: 1, else: 0

    raw = base_score + pattern_score + multi_pattern_bonus + complexity_bonus + visibility_bonus

    case purity do
      :pure -> raw
      :unknown -> max(1, round(raw * @unknown_weight))
    end
  end

  # A function is "complex enough" to be worth property-testing when it has
  # branching logic or a non-trivial number of AST nodes.
  #
  # NOTE: we deliberately do *not* count newlines in a stringified body:
  # `Metastatic.to_string/1` joins block statements with "; ", so multi-statement
  # bodies almost never contain a newline and the line-count heuristic was dead.
  defp complex_enough?(function_info) do
    meta_ast = meta_ast(function_info)

    has_multiple_clauses?(meta_ast, function_info.body) or
      node_count(meta_ast) > @complexity_node_threshold
  end

  # `Metastatic.postwalker/1` returns a lazy `Stream`, so it must be counted with
  # `Enum.count/1` (not `length/1`).
  defp node_count(meta_ast) do
    meta_ast
    |> Metastatic.postwalker()
    |> Enum.count()
  rescue
    _ -> 0
  end

  defp has_multiple_clauses?(meta_ast, legacy_body) do
    has_meta_clauses =
      Metastatic.postwalker(meta_ast)
      |> Enum.any?(fn
        {:pattern_match, _, _} -> true
        {:conditional, _, _} -> true
        {:function_call, meta, _} -> meta[:name] in ["case", "cond", "with", "if"]
        _ -> false
      end)

    has_meta_clauses or match?({:case, _, _}, legacy_body) or match?({:cond, _, _}, legacy_body) or
      match?({:with, _, _}, legacy_body)
  end

  # ----- Ranking --------------------------------------------------------------

  # Marks candidates that participate in a detected inverse function pair.
  defp mark_inverse_pair_members(candidates, inverse_pairs) do
    pair_members =
      inverse_pairs
      |> Enum.flat_map(fn pair -> [pair.forward, pair.inverse] end)
      |> MapSet.new(fn {module, name, arity} -> {module, name, arity} end)

    Enum.map(candidates, fn candidate ->
      member? = MapSet.member?(pair_members, {candidate.module, candidate.name, candidate.arity})
      %{candidate | inverse_pair: member?}
    end)
  end

  # Ranks candidates so the most actionable findings come first:
  #   1. inverse-pair members (round-trip properties are the highest-value tests)
  #   2. higher score
  #   3. `:pure` before `:unknown`
  #   4. public before private
  #   5. stable alphabetical tie-break
  # Assigns a 1-based `rank` to every candidate.
  defp rank_candidates(candidates) do
    candidates
    |> Enum.sort_by(fn candidate ->
      {if(candidate.inverse_pair, do: 0, else: 1), -candidate.score,
       purity_rank(candidate.purity), if(candidate.type == :public, do: 0, else: 1),
       candidate.module, candidate.name, candidate.arity}
    end)
    |> Enum.with_index(1)
    |> Enum.map(fn {candidate, rank} -> %{candidate | rank: rank} end)
  end

  defp purity_rank(:pure), do: 0
  defp purity_rank(:unknown), do: 1
  defp purity_rank(:impure), do: 2

  defp count_purities(candidates) do
    Enum.reduce(candidates, %{pure: 0, unknown: 0, impure: 0}, fn candidate, acc ->
      Map.update!(acc, candidate.purity, &(&1 + 1))
    end)
  end

  # ----- Config ---------------------------------------------------------------

  # `:pure_modules` may come from `.propwise.exs` (as a list of module atoms or
  # strings) or from caller options; caller options win.
  defp purity_opts(config, opts) do
    config_modules = Map.get(config, :pure_modules, [])
    opt_modules = Keyword.get(opts, :pure_modules, [])

    case opt_modules ++ config_modules do
      [] -> []
      modules -> [pure_modules: Enum.map(modules, &normalize_module/1)]
    end
  end

  defp normalize_module(module) when is_atom(module), do: module
  defp normalize_module("Elixir." <> rest), do: Module.concat([rest])
  defp normalize_module(string) when is_binary(string), do: Module.concat([string])
  defp normalize_module(other), do: other

  defp generate_suggestions(patterns, function_info, library, laws) do
    identity = identity_for(function_info, meta_ast(function_info))
    SuggestionGenerator.generate(patterns, function_info, library, laws, identity)
  end

  # The concrete identity element comes from the law table entry of the first
  # call in the body that declares one (e.g. `Map.merge` -> `%{}`).
  defp identity_for(_function_info, meta_ast) do
    meta_ast
    |> call_names()
    |> Enum.find_value(&LawTable.identity_for/1)
  rescue
    _ -> nil
  end
end
