defmodule PropWise.AnalyzerTest do
  use ExUnit.Case, async: true

  alias PropWise.Analyzer

  defp make_function(body, opts \\ []) do
    %{
      module: Keyword.get(opts, :module, "TestModule"),
      name: Keyword.get(opts, :name, :my_func),
      arity: Keyword.get(opts, :arity, 1),
      args: Keyword.get(opts, :args, [{:x, [], nil}]),
      body: body,
      file: "test.ex",
      line: 1,
      type: Keyword.get(opts, :type, :public)
    }
  end

  describe "analyze_function/2" do
    test "impure functions score 0" do
      func = make_function(quote(do: IO.puts("hello")))
      result = Analyzer.analyze_function(func)

      assert result.score == 0
      assert {:impure, _} = result.purity
    end

    test "pure function with no patterns gets base score only" do
      func = make_function(quote(do: x), name: :identity)
      result = Analyzer.analyze_function(func)

      # base(1) + public(1) = 2
      assert result.score == 2
      assert {:pure, []} = result.purity
    end

    test "public pure function with one pattern scores higher" do
      func = make_function(quote(do: Enum.map(list, &(&1 * 2))), name: :double_all)
      result = Analyzer.analyze_function(func)

      # base(1) + pattern(2) + public(1) = 4, possibly + complexity
      assert result.score >= 4
    end

    test "private functions score lower than public" do
      body = quote(do: Enum.map(list, &(&1 * 2)))
      public = make_function(body, name: :double_all, type: :public)
      private = make_function(body, name: :double_all, type: :private)

      pub_result = Analyzer.analyze_function(public)
      priv_result = Analyzer.analyze_function(private)

      assert pub_result.score > priv_result.score
    end

    test "multiple patterns give bonus score" do
      # Function with both collection_operation and validation patterns
      func =
        make_function(
          quote(do: Enum.filter(list, &(&1 > 0))),
          name: :valid_items?
        )

      result = Analyzer.analyze_function(func)
      # base(1) + 2 patterns(4) + multi_pattern_bonus(2) + public(1) = 8
      assert result.score >= 7
    end

    test "result contains expected keys" do
      func = make_function(quote(do: x + 1))
      result = Analyzer.analyze_function(func)

      assert Map.has_key?(result, :module)
      assert Map.has_key?(result, :name)
      assert Map.has_key?(result, :arity)
      assert Map.has_key?(result, :score)
      assert Map.has_key?(result, :purity)
      assert Map.has_key?(result, :patterns)
      assert Map.has_key?(result, :suggestions)
    end
  end

  describe "analyze_project/2" do
    test "analyzes a temporary project" do
      test_dir = "/tmp/propwise_analyzer_test_#{System.unique_integer([:positive])}"
      lib_dir = Path.join(test_dir, "lib")
      File.mkdir_p!(lib_dir)

      File.write!(Path.join(lib_dir, "math.ex"), """
      defmodule MyMath do
        def add(a, b), do: a + b

        def double_all(list), do: Enum.map(list, &(&1 * 2))

        def impure_func(x) do
          IO.puts(x)
          x
        end
      end
      """)

      result = Analyzer.analyze_project(test_dir, min_score: 0)

      File.rm_rf!(test_dir)

      assert result.total_functions == 3
      # impure_func should score 0
      impure = Enum.find(result.candidates, &(&1.name == :impure_func))
      assert impure == nil or impure.score == 0
    end

    test "min_score filters candidates" do
      test_dir = "/tmp/propwise_analyzer_test_#{System.unique_integer([:positive])}"
      lib_dir = Path.join(test_dir, "lib")
      File.mkdir_p!(lib_dir)

      File.write!(Path.join(lib_dir, "simple.ex"), """
      defmodule Simple do
        def identity(x), do: x
        def double_all(list), do: Enum.map(list, &(&1 * 2))
      end
      """)

      low = Analyzer.analyze_project(test_dir, min_score: 0)
      high = Analyzer.analyze_project(test_dir, min_score: 10)

      File.rm_rf!(test_dir)

      assert low.candidates_count >= high.candidates_count
    end
  end
end
