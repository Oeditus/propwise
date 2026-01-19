defmodule PropWise.CLI do
  @moduledoc """
  Command-line interface for PropWise.
  """

  alias PropWise.{Analyzer, Reporter}

  def main(args) do
    {opts, paths, _} =
      OptionParser.parse(args,
        strict: [
          min_score: :integer,
          format: :string,
          help: :boolean
        ],
        aliases: [
          m: :min_score,
          f: :format,
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
      IO.puts(:stderr, "Error: #{path} is not a valid directory")
      System.halt(1)
    end

    min_score = Keyword.get(opts, :min_score, 3)
    format = Keyword.get(opts, :format, "text") |> String.to_atom()

    # Only print status message for text format to avoid polluting JSON output
    if format == :text do
      IO.puts("Analyzing #{path}...")
    end

    result = Analyzer.analyze_project(path, min_score: min_score)

    Reporter.print_report(result, format: format)
  end

  defp print_help do
    IO.puts("""
    PropWise - Property-Based Testing Candidate Detector

    Usage:
      propwise [OPTIONS] [PATH]

    Arguments:
      [PATH]                  Path to the Elixir project to analyze (default: .)

    Options:
      -m, --min-score NUM     Minimum score for candidates (default: 3)
      -f, --format FORMAT     Output format: text or json (default: text)
      -h, --help              Show this help message

    Examples:
      propwise
      propwise --min-score 5
      propwise --format json
      propwise ./my_project

    The tool analyzes your Elixir codebase to find functions that are good
    candidates for property-based testing. It looks for:
      - Pure functions (no side effects)
      - Collection operations
      - Data transformations
      - Encoders/decoders and inverse function pairs
      - Validation functions
      - Algebraic structures

    Each candidate is scored based on multiple factors and includes
    suggestions for what properties to test.
    """)
  end
end
