defmodule PropWise.CommandLineTest do
  @moduledoc """
  Covers the CLI surface: argument parsing, file-list promotion, format
  validation and exit-code signalling. This module was previously untested.
  """

  use ExUnit.Case, async: true

  alias PropWise.CommandLine

  describe "parse_args/1" do
    test "defaults to the current directory when no path is given" do
      assert {[], ["."]} = CommandLine.parse_args([])
    end

    test "accepts a single path" do
      assert {[], ["lib"]} = CommandLine.parse_args(["lib"])
    end

    test "promotes multiple paths into the :files option" do
      assert {opts, ["."]} = CommandLine.parse_args(["lib/a.ex", "lib/b.ex"])
      assert opts[:files] == ["lib/a.ex", "lib/b.ex"]
    end

    test "parses short and long flags" do
      {opts, ["."]} = CommandLine.parse_args(["-m", "7", "--show-all", "--no-fail"])

      assert opts[:min_score] == 7
      assert opts[:show_all] == true
      assert opts[:no_fail] == true
    end

    test "parses --format and --library" do
      {opts, ["."]} = CommandLine.parse_args(["--format", "json", "-l", "proper"])

      assert opts[:format] == "json"
      assert opts[:library] == "proper"
    end

    test "parses --files as a comma-separated string" do
      {opts, ["."]} = CommandLine.parse_args(["--files", "lib/a.ex,lib/b.ex"])

      assert opts[:files] == "lib/a.ex,lib/b.ex"
    end
  end

  describe "run_analysis/3" do
    setup do
      dir = Path.join(System.tmp_dir!(), "propwise_cli_#{System.unique_integer([:positive])}")
      File.mkdir_p!(Path.join(dir, "lib"))

      File.write!(Path.join(dir, "lib/cli_mod.ex"), """
      defmodule CliMod do
        def double_all(list), do: Enum.map(list, &(&1 * 2))
      end
      """)

      on_exit(fn -> File.rm_rf!(dir) end)
      {:ok, dir: dir}
    end

    test "returns :suggestions_found when candidates exist", %{dir: dir} do
      assert {:suggestions_found, count} =
               CommandLine.run_analysis(dir, [min_score: 0], error: fn _ -> :ok end)

      assert count > 0
    end

    test "returns :ok when --no-fail is set", %{dir: dir} do
      assert :ok = CommandLine.run_analysis(dir, min_score: 0, no_fail: true)
    end

    test "returns :ok when nothing clears the threshold", %{dir: dir} do
      assert :ok = CommandLine.run_analysis(dir, min_score: 999)
    end

    test "returns :ok for json output regardless of findings", %{dir: dir} do
      assert :ok = CommandLine.run_analysis(dir, min_score: 0, format: "json")
    end

    test "reports an invalid path through the error callback" do
      parent = self()

      result =
        CommandLine.run_analysis("/definitely/not/a/path", [],
          error: fn message -> send(parent, {:error, message}) end
        )

      assert {:error, _} = result
      assert_received {:error, message}
      assert message =~ "not a valid file or directory"
    end

    test "warns about an unknown library and falls back to the default", %{dir: dir} do
      parent = self()

      CommandLine.run_analysis(dir, [min_score: 0, no_fail: true, library: "nonsense"],
        error: fn message -> send(parent, {:warning, message}) end
      )

      assert_received {:warning, message}
      assert message =~ "Unknown library"
    end

    test "accepts an unknown --format without leaking an atom", %{dir: dir} do
      assert :ok = CommandLine.run_analysis(dir, min_score: 999, format: "bogus")
    end

    test "writes to a file when --output is given", %{dir: dir} do
      output = Path.join(dir, "report.json")

      assert :ok =
               CommandLine.run_analysis(dir,
                 min_score: 0,
                 format: "json",
                 output: output
               )

      assert File.exists?(output)
      assert {:ok, _} = output |> File.read!() |> Jason.decode()
    end
  end

  describe "help_text/0" do
    test "documents every flag" do
      help = CommandLine.help_text()

      for flag <- [
            "--min-score",
            "--format",
            "--output",
            "--library",
            "--files",
            "--show-all",
            "--no-fail",
            "--help"
          ] do
        assert help =~ flag
      end
    end
  end
end
