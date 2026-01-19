defmodule PropWise.MixProject do
  use Mix.Project

  @version "0.1.0"
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
      extra_applications: [:logger, :jason]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
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
          PropWise.Analyzer
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
          PropWise.CLI,
          Mix.Tasks.Propwise
        ],
        Configuration: [
          PropWise.Config
        ]
      ]
    ]
  end
end
