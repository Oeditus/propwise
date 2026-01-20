defmodule Mix.Tasks.Propwise do
  @moduledoc """
  Analyzes an Elixir project for property-based testing candidates.

  ## Usage

      mix propwise [OPTIONS] [PATH]

  ## Arguments

    * `PATH` - Path to the Elixir project to analyze (default: current directory)

  ## Options

    * `-m, --min-score NUM` - Minimum score for candidates (default: 3)
    * `-f, --format FORMAT` - Output format: text or json (default: text)
    * `-l, --library LIB` - Property testing library: stream_data or proper (default: stream_data)
    * `-h, --help` - Show help message

  ## Examples

      mix propwise
      mix propwise --min-score 5
      mix propwise --format json
      mix propwise --library proper
      mix propwise ../other_project
  """

  @shortdoc "Analyzes code for property-based testing candidates"

  use Mix.Task

  alias PropWise.{Analyzer, Reporter}

  @impl Mix.Task
  def run(args) do
    {opts, paths, _} =
      OptionParser.parse(args,
        strict: [
          min_score: :integer,
          format: :string,
          library: :string,
          help: :boolean
        ],
        aliases: [
          m: :min_score,
          f: :format,
          l: :library,
          h: :help
        ]
      )

    if opts[:help] do
      print_help()
    else
      path = List.first(paths) || "."
      run_analysis(path, opts)
    end
  end

  defp run_analysis(path, opts) do
    unless File.dir?(path) do
      Mix.shell().error("Error: #{path} is not a valid directory")
      exit({:shutdown, 1})
    end

    min_score = Keyword.get(opts, :min_score, 4)
    format = Keyword.get(opts, :format, "text") |> String.to_atom()
    library = parse_library(opts)

    # Only print status message for text format to avoid polluting JSON output
    if format == :text do
      Mix.shell().info("Analyzing #{path}...")
    end

    analyzer_opts = [min_score: min_score]

    analyzer_opts =
      if library, do: Keyword.put(analyzer_opts, :library, library), else: analyzer_opts

    result = Analyzer.analyze_project(path, analyzer_opts)

    Reporter.print_report(result, format: format)

    # Exit with non-zero status if suggestions were found
    if result.candidates_count > 0 do
      exit({:shutdown, 1})
    end
  end

  defp parse_library(opts) do
    case Keyword.get(opts, :library) do
      nil ->
        nil

      "stream_data" ->
        :stream_data

      "proper" ->
        :proper

      other ->
        Mix.shell().error("Warning: Unknown library '#{other}', using default")
        nil
    end
  end

  defp print_help do
    Mix.shell().info("""
    PropWise - Property-Based Testing Candidate Detector

    Usage:
      mix propwise [OPTIONS] [PATH]

    Arguments:
      [PATH]                  Path to the Elixir project to analyze (default: .)

    Options:
      -m, --min-score NUM     Minimum score for candidates (default: 4)
      -f, --format FORMAT     Output format: text or json (default: text)
      -l, --library LIB       Property testing library: stream_data or proper (default: stream_data)
      -h, --help              Show this help message

    Examples:
      mix propwise
      mix propwise --min-score 5
      mix propwise --format json
      mix propwise --library proper
      mix propwise ../other_project

    The task analyzes your Elixir codebase to find functions that are good
    candidates for property-based testing. It looks for:
      - Pure functions (no side effects)
      - Collection operations
      - Data transformations
      - Encoders/decoders and inverse function pairs
      - Validation functions
      - Algebraic structures

    Each candidate is scored based on multiple factors and includes
    suggestions for what properties to test.

    Exit codes:
      0 - No suggestions found
      1 - Suggestions found or error occurred
    """)
  end
end
