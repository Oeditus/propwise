defmodule PropWise.PurityAnalyzerTest do
  use ExUnit.Case, async: true

  alias PropWise.PurityAnalyzer

  defp analyze(body, opts \\ []) do
    PurityAnalyzer.analyze(%{body: body}, opts)
  end

  describe "analyze/2 - three-state classification" do
    test "a body with only known-pure calls is :pure" do
      result = analyze(quote(do: Enum.map([1, 2, 3], fn x -> x * 2 end)))

      assert result.purity == :pure
      assert result.side_effects == []
      assert result.unresolved_calls == []
    end

    test "a body with no calls at all is :pure" do
      assert analyze(quote(do: x + y)).purity == :pure
    end

    test "a body calling an unknown module is :unknown, not :pure" do
      result = analyze(quote(do: MyApp.Helpers.normalize(x)))

      assert result.purity == :unknown
      assert result.side_effects == []
      assert result.unresolved_calls == ["MyApp.Helpers.normalize"]
    end

    test "a body calling an unresolved local function is :unknown" do
      result = analyze(quote(do: normalize(x)))

      assert result.purity == :unknown
      assert result.unresolved_calls == ["normalize"]
    end

    test "a body mixing pure and unresolved calls is :unknown" do
      result = analyze(quote(do: x |> Enum.map(& &1) |> MyApp.post_process()))

      assert result.purity == :unknown
    end

    test "a body with a side effect is :impure even if other calls are unresolved" do
      result = analyze(quote(do: MyApp.Helpers.normalize(IO.puts(x))))

      assert result.purity == :impure
      assert result.side_effects != []
    end

    test "purity is always one of the three atoms" do
      bodies = [
        quote(do: x),
        quote(do: IO.puts("hi")),
        quote(do: MyApp.Unknown.call(x)),
        quote(do: Enum.map(x, & &1)),
        quote(do: receive(do: (:ok -> :ok)))
      ]

      for body <- bodies do
        assert analyze(body).purity in [:pure, :unknown, :impure]
      end
    end
  end

  describe "analyze/2 - side effect detection" do
    test "detects IO side effects" do
      result = analyze(quote(do: IO.puts("hello")))

      assert result.purity == :impure

      assert match?([{:module_call, IO, :puts, 1}], result.side_effects) or
               match?([{:semantic_op, _, _}], result.side_effects)
    end

    test "detects File side effects" do
      result = analyze(quote(do: File.read!("test.txt")))

      assert result.purity == :impure

      assert match?([{:module_call, File, :read!, 1}], result.side_effects) or
               match?([{:semantic_op, _, _}], result.side_effects)
    end

    test "detects GenServer side effects" do
      result = analyze(quote(do: GenServer.call(pid, :message)))

      assert result.purity == :impure

      assert match?([{:module_call, GenServer, :call, 2}], result.side_effects) or
               match?([{:semantic_op, _, _}], result.side_effects)
    end

    test "detects receive blocks" do
      result = analyze(quote(do: receive(do: (:ok -> :ok))))

      assert result.purity == :impure
      assert {:receive_block} in result.side_effects
    end

    test "detects impure side effects from Metastatic MetaAST with op_kind" do
      meta_ast =
        {:function_call, [name: "Repo.get", op_kind: [domain: :db, operation: :retrieve]],
         [{:variable, [], "User"}, {:variable, [], "id"}]}

      result = PurityAnalyzer.analyze(%{body: meta_ast})

      assert result.purity == :impure
      assert {:semantic_op, :db, :retrieve} in result.side_effects
    end
  end

  describe "analyze/2 - :pure_modules option" do
    test "a call into a configured pure module resolves to :pure" do
      result = analyze(quote(do: MyApp.Math.add(a, b)), pure_modules: [MyApp.Math])

      assert result.purity == :pure
      assert result.unresolved_calls == []
    end

    test "a call into a non-configured module stays :unknown" do
      result = analyze(quote(do: MyApp.Other.add(a, b)), pure_modules: [MyApp.Math])

      assert result.purity == :unknown
    end

    test "configuring a module pure does not mask a real side effect elsewhere" do
      result = analyze(quote(do: MyApp.Math.add(a, IO.gets("x"))), pure_modules: [MyApp.Math])

      assert result.purity == :impure
    end
  end

  describe "classify/2 and pure?/2" do
    test "classify/2 returns the atom directly" do
      assert PurityAnalyzer.classify(%{body: quote(do: Enum.map(x, & &1))}) == :pure
      assert PurityAnalyzer.classify(%{body: quote(do: MyApp.f(x))}) == :unknown
      assert PurityAnalyzer.classify(%{body: quote(do: IO.puts(x))}) == :impure
    end

    test "pure?/1 is true only for :pure" do
      assert PurityAnalyzer.pure?(%{body: quote(do: Enum.map([1, 2, 3], fn x -> x * 2 end))})
      refute PurityAnalyzer.pure?(%{body: quote(do: MyApp.f(x))})
      refute PurityAnalyzer.pure?(%{body: quote(do: Logger.info(value))})
    end
  end
end
