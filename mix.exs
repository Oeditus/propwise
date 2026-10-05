defmodule Mix.Tasks.BundleDeps do
  use Mix.Task

  @shortdoc "Bundles compiled dependency beam and app files into propwise ebin"
  @moduledoc """
  Copies compiled dependency files (.beam and .app) into propwise's ebin directory
  so that when Mix builds an archive (.ez), all runtime dependencies are bundled.
  """
  def run(_args) do
    build_path = Mix.Project.build_path()
    lib_path = Path.join(build_path, "lib")
    app_name = Atom.to_string(Mix.Project.config()[:app])
    target_ebin = Path.join([lib_path, app_name, "ebin"])

    if File.dir?(lib_path) and File.dir?(target_ebin) do
      lib_path
      |> File.ls!()
      |> Enum.reject(&(&1 == app_name))
      |> Enum.each(fn dep_app ->
        dep_ebin = Path.join([lib_path, dep_app, "ebin"])

        if File.dir?(dep_ebin) do
          dep_ebin
          |> Path.join("*")
          |> Path.wildcard()
          |> Enum.each(fn dep_file ->
            if File.regular?(dep_file) do
              dest = Path.join(target_ebin, Path.basename(dep_file))
              File.copy!(dep_file, dest)
            end
          end)
        end
      end)
    end

    {:ok, []}
  end
end

defmodule PropWise.MixProject do
  use Mix.Project

  @version "0.4.2"
  @source_url "https://github.com/Oeditus/propwise"

  def project do
    [
      app: :propwise,
      version: @version,
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      escript: escript(),
      description: description(),
      package: package(),
      docs: docs(),
      aliases: aliases(),
      dialyzer: dialyzer(),
      test_coverage: [tool: ExCoveralls],
      name: "PropWise",
      source_url: @source_url,
      homepage_url: @source_url
    ]
  end

  def cli do
    [
      preferred_envs: [
        coveralls: :test,
        "coveralls.detail": :test,
        "coveralls.post": :test,
        "coveralls.html": :test,
        "coveralls.json": :test
      ]
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger, :jason, :metastatic]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:metastatic, "~> 0.29"},
      {:marcli, "~> 0.4"},
      # Runtime dependency needed for JSON output
      {:jason, "~> 1.4"},
      {:ex_doc, "~> 0.34", only: :dev, runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:excoveralls, "~> 0.18", only: :test, runtime: false}
    ]
  end

  defp escript do
    [main_module: PropWise.CLI]
  end

  defp aliases do
    [
      "archive.build": ["compile", "bundle_deps", "archive.build --no-compile"],
      quality: ["format", "credo --strict", "dialyzer"],
      "quality.ci": [
        "format --check-formatted",
        "credo --strict",
        "dialyzer"
      ]
    ]
  end

  defp dialyzer do
    [
      plt_file: {:no_warn, "priv/plts/dialyzer.plt"},
      plt_add_apps: [:mix]
    ]
  end

  defp description do
    """
    AST-based analyzer for identifying property-based testing candidates in Elixir codebases.
    Detects pure functions, identifies testable patterns, finds inverse function pairs,
    and generates concrete property-based test suggestions.
    """
  end

  defp package do
    [
      name: "propwise",
      files: ~w(lib mix.exs README.md LICENSE CHANGELOG.md stuff/docs/SCORING.md),
      licenses: ["MIT"],
      links: %{
        "GitHub" => @source_url,
        "Changelog" => "#{@source_url}/blob/main/CHANGELOG.md"
      },
      maintainers: ["Aleksei Matiushkin"],
      # Enable installation as a Mix archive
      files_to_archive: ~w(lib mix.exs README.md LICENSE)
    ]
  end

  defp docs do
    [
      main: "readme",
      source_ref: "v#{@version}",
      source_url: @source_url,
      logo: "stuff/img/logo-48x48.png",
      extras: [
        "README.md",
        "CHANGELOG.md",
        "stuff/docs/SCORING.md",
        "LICENSE"
      ],
      groups_for_extras: [
        Guides: ~r/stuff\/docs\/.?/
      ],
      formatters: ["html"],
      authors: ["Aleksei Matiushkin"],
      api_reference: false,
      groups_for_modules: [
        Core: [
          PropWise,
          PropWise.Analyzer,
          PropWise.SuggestionGenerator
        ],
        "AST Analysis": [
          PropWise.Parser,
          PropWise.PurityAnalyzer,
          PropWise.PatternDetector
        ],
        Output: [
          PropWise.Reporter
        ],
        "Command Line": [
          PropWise.CommandLine,
          PropWise.CLI,
          Mix.Tasks.Propwise
        ],
        "Data Structures": [
          PropWise.FunctionInfo,
          PropWise.Candidate
        ],
        Configuration: [
          PropWise.Config
        ]
      ]
    ]
  end
end
