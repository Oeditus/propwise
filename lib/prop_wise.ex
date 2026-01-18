defmodule PropWise do
  @moduledoc """
  PropWise - AST-based analyzer for identifying property-based testing candidates.

  PropWise analyzes Elixir codebases to find functions that would benefit from
  property-based testing. It uses AST analysis to:

  - Detect pure functions (no side effects)
  - Identify common patterns (collections, transformations, validation, etc.)
  - Find inverse function pairs (encode/decode, serialize/deserialize, etc.)
  - Score and rank candidates by testability
  - Provide specific testing suggestions

  ## Usage

  As a library:

      result = PropWise.analyze("./my_project")
      PropWise.print_report(result)

  As a command-line tool:

      $ mix escript.build
      $ ./propwise ./my_project
      $ ./propwise --min-score 5 --format json ./my_project

  ## Configuration

  You can customize the minimum score threshold:

      PropWise.analyze("./my_project", min_score: 5)

  Output formats: `:text` (default) or `:json`

      PropWise.print_report(result, format: :json)
  """

  alias PropWise.{Analyzer, Reporter}

  @doc """
  Analyzes an Elixir project for property-based testing candidates.

  ## Parameters

    - `path` - Path to the Elixir project directory
    - `opts` - Keyword list of options:
      - `:min_score` - Minimum score for candidates (default: 3)

  ## Returns

  A map containing:
    - `:candidates` - List of function candidates with scores
    - `:inverse_pairs` - Detected inverse function pairs
    - `:total_functions` - Total number of functions analyzed
    - `:candidates_count` - Number of candidates found

  ## Examples

      result = PropWise.analyze(".")
      result = PropWise.analyze("./lib", min_score: 5)
  """
  def analyze(path, opts \\ []) do
    Analyzer.analyze_project(path, opts)
  end

  @doc """
  Prints the analysis report.

  ## Parameters

    - `analysis_result` - Result from `analyze/2`
    - `opts` - Keyword list of options:
      - `:format` - Output format: `:text` or `:json` (default: `:text`)

  ## Examples

      result = PropWise.analyze(".")
      PropWise.print_report(result)
      PropWise.print_report(result, format: :json)
  """
  def print_report(analysis_result, opts \\ []) do
    Reporter.print_report(analysis_result, opts)
  end
end
