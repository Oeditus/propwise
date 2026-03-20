defmodule PropWise.CLI do
  @moduledoc """
  Command-line interface for PropWise (escript entry point).
  """

  alias PropWise.CommandLine

  def main(args) do
    {opts, paths} = CommandLine.parse_args(args)

    if opts[:help] do
      IO.puts(CommandLine.help_text())
    else
      path = List.first(paths) || "."

      case CommandLine.run_analysis(path, opts) do
        {:suggestions_found, _} -> System.halt(1)
        {:error, _} -> System.halt(1)
        :ok -> :ok
      end
    end
  end
end
