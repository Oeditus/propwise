defmodule PropWise.RegressionTest do
  @moduledoc """
  Regression tests for issues found during the full project audit.

  Each `describe` block pins down a specific defect so it cannot reappear.
  """

  use ExUnit.Case, async: true

  alias PropWise.{Analyzer, Config, PatternDetector, Reporter, SuggestionGenerator}

  defp function_info(attrs) do
    Map.merge(
      %{
        module: "MyApp.Deep.Nested.Encoder",
        name: :encode,
        arity: 1,
        args: [],
        body: quote(do: nil),
        file: "lib/my_app/deep/nested/encoder.ex",
        line: 1,
        type: :public
      },
      Map.new(attrs)
    )
  end

  defp detector_patterns(name, body) do
    function_info(name: name, body: body)
    |> PatternDetector.detect_patterns()
    |> Enum.map(&elem(&1, 0))
  end

  describe "audit #1: Regex.match?/2 is not a parser" do
    test "a predicate using Regex.match? is validation-only, never a parser" do
      body =
        quote do
          Regex.match?(~r/^[a-z]+$/, email)
        end

      patterns = detector_patterns(:valid_email?, body)

      assert :validation in patterns
      refute :parser in patterns
    end

    test "a ?-suffixed function is never classified as a parser" do
      refute :parser in detector_patterns(:parseable?, quote(do: true))
    end

    test "Regex.run still counts as string parsing" do
      body = quote(do: Regex.run(~r/(\d+)/, input))
      assert :parser in detector_patterns(:extract_number, body)
    end
  end

  describe "audit #2: inverse pairs are found in O(n) via an index" do
    test "finds encode/decode within the same module" do
      functions = [
        function_info(name: :encode),
        function_info(name: :decode)
      ]

      assert [%{forward: {_, :encode, _}, inverse: {_, :decode, _}}] =
               PatternDetector.find_inverse_pairs(functions)
    end

    test "does not report cross-module pairs" do
      functions = [
        function_info(module: "A", name: :encode),
        function_info(module: "B", name: :decode)
      ]

      assert [] = PatternDetector.find_inverse_pairs(functions)
    end

    test "does not report a function as its own inverse" do
      functions = [function_info(name: :encode)]
      assert [] = PatternDetector.find_inverse_pairs(functions)
    end

    test "reports each pair exactly once" do
      functions = [
        function_info(name: :encode),
        function_info(name: :decode)
      ]

      pairs = PatternDetector.find_inverse_pairs(functions)

      assert length(pairs) == length(Enum.uniq_by(pairs, &{&1.forward, &1.inverse}))
    end

    test "handles to_/from_ prefix pairs" do
      functions = [
        function_info(name: :to_string),
        function_info(name: :from_string)
      ]

      assert [_] = PatternDetector.find_inverse_pairs(functions)
    end
  end

  describe "audit #3: suggestions use the full module name" do
    test "nested modules are not truncated to the last segment" do
      info = function_info(name: :encode, arity: 1)

      suggestions = SuggestionGenerator.generate([{:encoder_decoder, "r"}], info, :stream_data)

      assert Enum.any?(suggestions, &String.contains?(&1, "MyApp.Deep.Nested.Encoder.encode("))
      refute Enum.any?(suggestions, &String.contains?(&1, " Encoder.encode("))
    end

    test "round-trip suggestion flags the return shape as a TODO" do
      info = function_info(name: :encode, arity: 1)

      suggestions = SuggestionGenerator.generate([{:encoder_decoder, "r"}], info, :stream_data)

      assert Enum.any?(suggestions, &String.contains?(&1, "TODO"))
    end
  end

  describe "audit #4: compress/decompress inverse mapping" do
    test "compress maps to decompress, not to itself" do
      info = function_info(name: :compress_data, arity: 1)

      suggestions = SuggestionGenerator.generate([{:encoder_decoder, "r"}], info, :stream_data)

      assert Enum.any?(suggestions, &String.contains?(&1, "decompress_data"))
    end

    test "decompress maps to compress" do
      info = function_info(name: :decompress_data, arity: 1)

      suggestions = SuggestionGenerator.generate([{:encoder_decoder, "r"}], info, :stream_data)

      assert Enum.any?(suggestions, &String.contains?(&1, "compress_data("))
    end
  end

  describe "audit #5: call sites are built structurally, not by regex" do
    test "multi-arity calls keep every argument" do
      info = function_info(name: :combine, arity: 3, module: "M")

      suggestions = SuggestionGenerator.generate([{:transformation, "r"}], info, :stream_data)

      assert Enum.any?(suggestions, &String.contains?(&1, "M.combine(a, b, c)"))
    end

    test "collection suggestions replace only the first argument" do
      info = function_info(name: :transform, arity: 2, module: "M")

      suggestions =
        SuggestionGenerator.generate([{:collection_operation, "r"}], info, :stream_data)

      assert Enum.any?(suggestions, &String.contains?(&1, "M.transform(list, b)"))
    end

    test "zero-arity calls do not gain a spurious argument" do
      info = function_info(name: :now, arity: 0, module: "M")

      suggestions = SuggestionGenerator.generate([{:transformation, "r"}], info, :stream_data)

      assert Enum.any?(suggestions, &String.contains?(&1, "M.now()"))
      refute Enum.any?(suggestions, &String.contains?(&1, "M.now(input)"))
    end
  end

  describe "audit #6: complexity bonus is AST-based, not newline-based" do
    test "a multi-statement body is considered complex" do
      body =
        quote do
          a = x + 1
          b = a * 2
          c = b - 3
          d = c / 4
          {a, b, c, d}
        end

      result = Analyzer.analyze_function(function_info(name: :steps, body: body), :stream_data)

      # base(1) + public(1) = 2, plus complexity(1) => 3
      assert result.score >= 3
    end

    test "a trivial one-liner does not earn the complexity bonus" do
      result =
        Analyzer.analyze_function(function_info(name: :inc, body: quote(do: x + 1)), :stream_data)

      # base(1) + public(1) only
      assert result.score == 2
    end

    test "conditional logic earns the complexity bonus" do
      body =
        quote do
          case x do
            0 -> :zero
            _ -> :other
          end
        end

      result = Analyzer.analyze_function(function_info(name: :classify, body: body), :stream_data)

      assert result.score >= 3
    end
  end

  describe "audit #7: config errors are surfaced, not swallowed" do
    setup do
      dir = Path.join(System.tmp_dir!(), "propwise_reg_#{System.unique_integer([:positive])}")
      File.mkdir_p!(dir)
      on_exit(fn -> File.rm_rf!(dir) end)
      {:ok, dir: dir}
    end

    test "reports a syntax error through :on_error", %{dir: dir} do
      File.write!(Path.join(dir, ".propwise.exs"), "this is not elixir !!!")

      parent = self()

      config =
        Config.load(dir, on_error: fn message -> send(parent, {:config_error, message}) end)

      assert_received {:config_error, message}
      assert message =~ ".propwise.exs"
      assert config.analyze_paths == ["lib"]
    end

    test "reports a non-map value through :on_error", %{dir: dir} do
      File.write!(Path.join(dir, ".propwise.exs"), ~s("just a string"))

      parent = self()

      config =
        Config.load(dir, on_error: fn message -> send(parent, {:config_error, message}) end)

      assert_received {:config_error, _}
      assert config.analyze_paths == ["lib"]
    end

    test "stays silent without :on_error", %{dir: dir} do
      File.write!(Path.join(dir, ".propwise.exs"), ~s("just a string"))

      assert Config.load(dir).analyze_paths == ["lib"]
    end
  end

  describe "audit #8: reporter handles an empty project" do
    test "warns when no functions were found" do
      report =
        Reporter.format_report(%{
          candidates: [],
          inverse_pairs: [],
          total_functions: 0,
          candidates_count: 0,
          dropped_count: 0
        })

      assert report =~ "no `.ex` files found"
    end

    test "does not emit a coverage line when nothing was analysed" do
      report =
        Reporter.format_report(%{
          candidates: [],
          inverse_pairs: [],
          total_functions: 0,
          candidates_count: 0,
          dropped_count: 0
        })

      refute report =~ "Coverage"
    end
  end

  describe "audit #9: rank is always present on candidates" do
    test "analyze_function assigns a rank" do
      result = Analyzer.analyze_function(function_info(name: :identity, body: quote(do: x)))

      assert result.rank >= 1
    end

    test "project analysis assigns unique 1-based ranks" do
      dir = Path.join(System.tmp_dir!(), "propwise_rank_#{System.unique_integer([:positive])}")
      File.mkdir_p!(Path.join(dir, "lib"))

      File.write!(Path.join(dir, "lib/ranked.ex"), """
      defmodule Ranked do
        def alpha(list), do: Enum.map(list, &(&1 * 2))
        def beta(list), do: Enum.filter(list, &(&1 > 0))
      end
      """)

      result = PropWise.analyze(dir, min_score: 0)
      File.rm_rf!(dir)

      ranks = result.candidates |> Enum.map(& &1.rank) |> Enum.sort()
      assert ranks == Enum.to_list(1..length(result.candidates))
    end
  end
end
