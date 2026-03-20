defmodule PropWise.Config do
  @moduledoc """
  Handles configuration loading from `.propwise.exs` file.

  **Security note**: Configuration is loaded via `Code.eval_file/1`, which
  executes arbitrary Elixir code. Only analyze projects you trust, or review
  the `.propwise.exs` file before running PropWise on untrusted codebases.
  """

  @default_config %{
    analyze_paths: ["lib"],
    library: :stream_data
  }

  @doc """
  Loads configuration from .propwise.exs in the project root.
  Falls back to default configuration if file doesn't exist.
  """
  @spec load(String.t()) :: map()
  def load(project_path) do
    config_file = Path.join(project_path, ".propwise.exs")

    if File.exists?(config_file) do
      load_config_file(config_file)
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

  defp normalize_library(:stream_data), do: :stream_data
  defp normalize_library(:proper), do: :proper
  defp normalize_library("stream_data"), do: :stream_data
  defp normalize_library("proper"), do: :proper
  defp normalize_library(_), do: @default_config.library

  defp load_config_file(config_file) do
    {config, _bindings} = Code.eval_file(config_file)

    # Validate that it's a map or keyword list
    case config do
      config when is_map(config) ->
        config

      config when is_list(config) ->
        Map.new(config)

      _ ->
        # Silently fall back to defaults to avoid polluting output
        @default_config
    end
  rescue
    _e ->
      # Silently fall back to defaults to avoid polluting output
      @default_config
  end
end
