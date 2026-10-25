defmodule PropWise.CommandLine do
  @moduledoc """
  Shared command-line argument parsing and analysis logic for both
  the escript CLI and the Mix task.
  """

  alias PropWise.{Analyzer, Baseline, Reporter}

  @parse_opts [
    strict: [
      min_score: :integer,
      format: :string,
      output: :string,
      library: :string,
      files: :string,
      no_fail: :boolean,
      show_all: :boolean,
      baseline: :string,
      write_baseline: :string,
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

    case paths do
      [] ->
        {opts, ["."]}

      [path] ->
        {opts, [path]}

      multiple_paths ->
        opts = Keyword.put_new(opts, :files, multiple_paths)
        {opts, ["."]}
    end
  end

  @spec run_analysis(String.t(), keyword(), keyword()) ::
          :ok | {:suggestions_found, non_neg_integer()} | {:error, String.t()}
  def run_analysis(path, opts, callbacks \\ []) do
    do_run_analysis(path, opts, callbacks)
  catch
    {:invalid_path, p} -> {:error, "#{p} is not a valid file or directory"}
    {:invalid_baseline, p, reason} -> {:error, "cannot read baseline #{p}: #{inspect(reason)}"}
  end

  defp do_run_analysis(path, opts, callbacks) do
    format = parse_format(Keyword.get(opts, :format, "text"))
    error_fn = Keyword.get(callbacks, :error, &default_error/1)
    info_fn = Keyword.get(callbacks, :info, &default_info/1)

    files_opt = Keyword.get(opts, :files)

    valid_target? =
      File.dir?(path) or File.regular?(path) or not is_nil(files_opt)

    unless valid_target? do
      error_fn.("Error: #{path} is not a valid file or directory")
      throw({:invalid_path, path})
    end

    min_score = Keyword.get(opts, :min_score, 4)
    library = parse_library(opts, format, error_fn)
    show_all = Keyword.get(opts, :show_all, false)

    if format == :text do
      info_fn.("Analyzing #{path}...")
    end

    analyzer_opts =
      [min_score: min_score, library: library, files: files_opt]
      |> Enum.reject(fn {_key, value} -> is_nil(value) end)

    config_error = fn message -> error_fn.(message) end

    result =
      Analyzer.analyze_project(path, Keyword.put(analyzer_opts, :on_config_error, config_error))

    # `--write-baseline` snapshots the *unfiltered* result, then exits without
    # reporting: writing a baseline is a setup action, not an analysis run.
    case Keyword.get(opts, :write_baseline) do
      nil ->
        report_and_exit(result, opts, format, library, show_all, error_fn)

      baseline_path ->
        write_baseline(result, baseline_path, format, info_fn, error_fn)
    end
  end

  defp write_baseline(result, baseline_path, format, info_fn, error_fn) do
    baseline = Baseline.from_result(result)

    case Baseline.write(baseline_path, baseline) do
      :ok ->
        if format == :text do
          info_fn.(
            "Wrote baseline with #{Baseline.size(baseline)} candidate(s) to #{baseline_path}"
          )
        end

        :ok

      {:error, reason} ->
        error_fn.("Error: could not write baseline #{baseline_path}: #{inspect(reason)}")
        throw({:invalid_baseline, baseline_path, reason})
    end
  end

  defp report_and_exit(result, opts, format, library, show_all, error_fn) do
    {result, baseline_info} = apply_baseline(result, opts, format, error_fn)

    output_file = Keyword.get(opts, :output)

    report_opts =
      [format: format, show_all: show_all, library: library, baseline: baseline_info]
      |> Enum.reject(fn {_key, value} -> is_nil(value) end)

    if output_file do
      output = Reporter.format_report(result, report_opts)
      File.write!(output_file, output)
    else
      Reporter.print_report(result, report_opts)
    end

    no_fail = Keyword.get(opts, :no_fail, false)

    if format != :json and result.candidates_count > 0 and not no_fail do
      {:suggestions_found, result.candidates_count}
    else
      :ok
    end
  end

  # Applies `--baseline` filtering when requested. Returns the (possibly
  # filtered) result plus a small map describing the baseline for the report.
  defp apply_baseline(result, opts, format, error_fn) do
    case Keyword.get(opts, :baseline) do
      nil ->
        {result, nil}

      baseline_path ->
        case Baseline.read(baseline_path) do
          {:ok, baseline} ->
            filtered = Baseline.apply_to_result(baseline, result)
            announce_suppressed(result, filtered, format)

            {filtered, %{path: baseline_path, size: Baseline.size(baseline)}}

          {:error, reason} ->
            error_fn.("Error: cannot read baseline #{baseline_path}: #{inspect(reason)}")
            throw({:invalid_baseline, baseline_path, reason})
        end
    end
  end

  defp announce_suppressed(_result, _filtered, format) when format != :text, do: :ok

  defp announce_suppressed(result, filtered, :text) do
    suppressed = result.candidates_count - filtered.candidates_count

    if suppressed > 0 do
      IO.puts("Baseline: #{suppressed} previously accepted candidate(s) suppressed.")
    end
  end

  # Validate the format up front instead of leaking an atom per bogus value.
  defp parse_format(value) when value in ["json", :json], do: :json
  defp parse_format(value) when value in ["markdown", :markdown], do: :markdown
  defp parse_format(_), do: :text

  @spec help_text() :: String.t()
  def help_text do
    """
    PropWise - Property-Based Testing Candidate Detector

    Usage:
      propwise [OPTIONS] [PATH_OR_FILES...]

    Arguments:
      [PATH_OR_FILES]         Path to project directory, single file, or list of files

    Options:
      -m, --min-score NUM     Minimum score for candidates (default: 4)
      -f, --format FORMAT     Output format: text or json (default: text)
      -o, --output FILE       Write output to file instead of stdout
      -l, --library LIB       Property testing library: stream_data or proper (default: stream_data)
      --files FILES           Comma-separated list of specific files to analyze (ideal for PRs)
      --baseline FILE         Only report candidates that are new or whose score increased
                              relative to the given baseline file (CI ratcheting)
      --write-baseline FILE   Write a baseline snapshot of the current candidates and exit
      --show-all              Show all findings instead of the top 3 (still ranked)
      --no-fail               Exit with code 0 even when suggestions are found
      -h, --help              Show this help message

    Examples:
      propwise
      propwise --min-score 5
      propwise --format json
      propwise --files lib/my_app/user.ex,lib/my_app/auth.ex
      propwise lib/my_app/user.ex
      propwise ./my_project

      # CI ratcheting: accept today's state, fail only on regressions
      propwise --write-baseline .propwise/baseline.json
      propwise --baseline .propwise/baseline.json

    The tool analyzes your Elixir codebase to find functions that are good
    candidates for property-based testing. It looks for:
      - Pure functions (no side effects)
      - Collection operations
      - Data transformations
      - Encoders/decoders and inverse function pairs
      - Validation functions
      - Algebraic structures

    Each candidate is scored based on multiple factors, carries an inferred
    set of algebraic laws (e.g. `Enum.reverse` implies involution), and includes
    ready-to-use property test suggestions.

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
