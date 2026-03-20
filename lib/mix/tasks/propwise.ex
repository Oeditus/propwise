defmodule Mix.Tasks.Propwise do
  @moduledoc """
  Analyzes an Elixir project for property-based testing candidates.

  ## Usage

      mix propwise [OPTIONS] [PATH]

  ## Options

    * `-m, --min-score NUM` - Minimum score for candidates (default: 4)
    * `-f, --format FORMAT` - Output format: text or json (default: text)
    * `-o, --output FILE` - Write output to file instead of stdout
    * `-l, --library LIB` - Property testing library: stream_data or proper (default: stream_data)
    * `--no-fail` - Exit with code 0 even when suggestions are found (default: false)
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

  alias PropWise.CommandLine

  @impl Mix.Task
  def run(args) do
    {opts, paths} = CommandLine.parse_args(args)

    if opts[:help] do
      Mix.shell().info(CommandLine.help_text())
    else
      path = List.first(paths) || "."

      shell = Mix.shell()

      callbacks = [
        error: &shell.error/1,
        info: &shell.info/1
      ]

      case CommandLine.run_analysis(path, opts, callbacks) do
        {:suggestions_found, _} -> exit({:shutdown, 1})
        {:error, _} -> exit({:shutdown, 1})
        :ok -> :ok
      end
    end
  end
end
