defmodule PropWise.MixProject do
  use Mix.Project

  def project do
    [
      app: :propwise,
      version: "0.1.0",
      elixir: "~> 1.19",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      escript: escript(),
      description:
        "AST-based analyzer for identifying property-based testing candidates in Elixir codebases",
      package: package()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:jason, "~> 1.4"}
    ]
  end

  defp escript do
    [main_module: PropWise.CLI]
  end

  defp package do
    [
      licenses: ["MIT"],
      links: %{"GitHub" => "https://github.com/am-kantox/propwise"}
    ]
  end
end
