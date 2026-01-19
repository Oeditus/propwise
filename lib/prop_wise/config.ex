defmodule PropWise.Config do
  @moduledoc """
  Handles configuration loading from .propwise.exs file.
  """

  @default_config %{
    analyze_paths: ["lib"]
  }

  @doc """
  Loads configuration from .propwise.exs in the project root.
  Falls back to default configuration if file doesn't exist.
  """
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
  def analyze_paths(project_path) do
    config = load(project_path)
    Map.get(config, :analyze_paths, @default_config.analyze_paths)
  end

  defp load_config_file(config_file) do
    {config, _bindings} = Code.eval_file(config_file)

    # Validate that it's a map or keyword list
    case config do
      config when is_map(config) ->
        config

      config when is_list(config) ->
        Map.new(config)

      _ ->
        IO.warn("Invalid configuration in #{config_file}, using defaults")
        @default_config
    end
  rescue
    e ->
      IO.warn("Error loading #{config_file}: #{inspect(e)}, using defaults")
      @default_config
  end
end
