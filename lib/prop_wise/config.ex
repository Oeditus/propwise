defmodule PropWise.Config do
  @moduledoc """
  Handles configuration loading from `.propwise.exs` file.

  **Security note**: Configuration is loaded via `Code.eval_file/1`, which
  executes arbitrary Elixir code. Only analyze projects you trust, or review
  the `.propwise.exs` file before running PropWise on untrusted codebases.
  """

  @default_config %{
    analyze_paths: ["lib"],
    library: :stream_data,
    pure_modules: []
  }

  @doc """
  Loads configuration from .propwise.exs in the project root.
  Falls back to default configuration if file doesn't exist or is invalid.

  When `:on_error` is given as a 1-arity function, configuration problems are
  reported through it instead of being silently swallowed — a typo in
  `.propwise.exs` should never manifest as a mysterious "0 functions" report.
  """
  @spec load(String.t(), keyword()) :: map()
  def load(project_path, opts \\ []) do
    config_file = Path.join(project_path, ".propwise.exs")
    on_error = Keyword.get(opts, :on_error)

    if File.exists?(config_file) do
      load_config_file(config_file, on_error)
    else
      @default_config
    end
  end

  @doc """
  Returns the paths to analyze for a given project.
  """
  @spec analyze_paths(String.t()) :: [String.t()]
  def analyze_paths(project_path) do
    config = load(project_path)
    Map.get(config, :analyze_paths, @default_config.analyze_paths)
  end

  @doc """
  Returns the property-based testing library to use for suggestions.
  Supported values: :stream_data, :proper
  """
  @spec library(String.t()) :: :stream_data | :proper
  def library(project_path) do
    config = load(project_path)
    lib = Map.get(config, :library, @default_config.library)
    normalize_library(lib)
  end

  @doc """
  Returns the modules whose functions are known to be pure.

  Accepts module atoms or strings (`MyApp.Math` or `"MyApp.Math"`); the
  analyzer normalises them.
  """
  @spec pure_modules(String.t()) :: [module() | String.t()]
  def pure_modules(project_path) do
    config = load(project_path)
    Map.get(config, :pure_modules, @default_config.pure_modules)
  end

  defp normalize_library(:stream_data), do: :stream_data
  defp normalize_library(:proper), do: :proper
  defp normalize_library("stream_data"), do: :stream_data
  defp normalize_library("proper"), do: :proper
  defp normalize_library(_), do: @default_config.library

  defp load_config_file(config_file, on_error) do
    {config, _bindings} = Code.eval_file(config_file)

    # Validate that it's a map or keyword list
    case config do
      config when is_map(config) ->
        config

      config when is_list(config) ->
        Map.new(config)

      other ->
        report(
          on_error,
          "ignoring #{config_file}: expected a map or keyword list, got: #{inspect(other)}"
        )

        @default_config
    end
  rescue
    e ->
      report(on_error, "ignoring #{config_file}: #{Exception.message(e)}")
      @default_config
  end

  defp report(nil, _message), do: :ok
  defp report(fun, message) when is_function(fun, 1), do: fun.(message)
end
