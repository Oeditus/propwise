defmodule PropWise.CommandLine do
  @moduledoc """
  Shared command-line argument parsing and analysis logic for both
  the escript CLI and the Mix task.
  """

  alias PropWise.{Analyzer, Reporter}

  @parse_opts [
    strict: [
      min_score: :integer,
      format: :string,
      output: :string,
      library: :string,
      no_fail: :boolean,
      help: :boolean
    ],
    aliases: [
      m: :min_score,
      f: :format,
      o: :output,
      l: :library,
      h: :help
    ]
  ]

  @spec parse_args([String.t()]) :: {keyword(), [String.t()]}
  def parse_args(args) do
    {opts, paths, _} = OptionParser.parse(args, @parse_opts)
    {opts, paths}
  end

  @spec run_analysis(String.t(), keyword(), keyword()) ::
          :ok | {:suggestions_found, non_neg_integer()} | {:error, String.t()}
  def run_analysis(path, opts, callbacks \\ []) do
    do_run_analysis(path, opts, callbacks)
  catch
    {:invalid_path, p} -> {:error, "#{p} is not a valid directory"}
  end

  defp do_run_analysis(path, opts, callbacks) do
    format = Keyword.get(opts, :format, "text") |> String.to_atom()
    error_fn = Keyword.get(callbacks, :error, &default_error/1)
    info_fn = Keyword.get(callbacks, :info, &default_info/1)

    unless File.dir?(path) do
      error_fn.("Error: #{path} is not a valid directory")
      throw({:invalid_path, path})
    end

    min_score = Keyword.get(opts, :min_score, 4)
    library = parse_library(opts, format, error_fn)

    if format == :text do
      info_fn.("Analyzing #{path}...")
    end

    analyzer_opts = [min_score: min_score]

    analyzer_opts =
      if library, do: Keyword.put(analyzer_opts, :library, library), else: analyzer_opts

    result = Analyzer.analyze_project(path, analyzer_opts)

    output_file = Keyword.get(opts, :output)

    if output_file do
      output = Reporter.format_report(result, format: format)
      File.write!(output_file, output)
    else
      Reporter.print_report(result, format: format)
    end

    no_fail = Keyword.get(opts, :no_fail, false)

    if format != :json and result.candidates_count > 0 and not no_fail do
      {:suggestions_found, result.candidates_count}
    else
      :ok
    end
  end

  @spec help_text() :: String.t()
  def help_text do
    """
    PropWise - Property-Based Testing Candidate Detector

    Usage:
      propwise [OPTIONS] [PATH]

    Arguments:
      [PATH]                  Path to the Elixir project to analyze (default: .)

    Options:
      -m, --min-score NUM     Minimum score for candidates (default: 4)
      -f, --format FORMAT     Output format: text or json (default: text)
      -o, --output FILE       Write output to file instead of stdout
      -l, --library LIB       Property testing library: stream_data or proper (default: stream_data)
      --no-fail               Exit with code 0 even when suggestions are found
      -h, --help              Show this help message

    Examples:
      propwise
      propwise --min-score 5
      propwise --format json
      propwise --library proper
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

    Exit codes:
      0 - No suggestions found
      1 - Suggestions found or error occurred
    """
  end

  defp parse_library(opts, format, error_fn) do
    case Keyword.get(opts, :library) do
      nil ->
        nil

      "stream_data" ->
        :stream_data

      "proper" ->
        :proper

      other ->
        if format == :text do
          error_fn.("Warning: Unknown library '#{other}', using default")
        end

        nil
    end
  end

  defp default_error(msg), do: IO.puts(:stderr, msg)
  defp default_info(msg), do: IO.puts(msg)
end
