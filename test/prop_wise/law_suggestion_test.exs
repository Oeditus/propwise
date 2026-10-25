defmodule PropWise.LawSuggestionTest do
  @moduledoc """
  Tests that inferred laws render into correct, arity-appropriate properties.
  """

  use ExUnit.Case, async: true

  alias PropWise.SuggestionGenerator

  defp info(name, arity, opts \\ []) do
    %{
      module: Keyword.get(opts, :module, "MyApp.Config"),
      name: name,
      arity: arity,
      args: [],
      body: quote(do: nil),
      file: "lib/x.ex",
      line: 1,
      type: :public
    }
  end

  defp generate(laws, function_info, opts \\ []) do
    SuggestionGenerator.generate(
      Keyword.get(opts, :patterns, []),
      function_info,
      Keyword.get(opts, :library, :stream_data),
      laws,
      Keyword.get(opts, :identity)
    )
  end

  describe "associativity" do
    test "renders f(f(a, b), c) == f(a, f(b, c)) for a binary function" do
      suggestions = generate([:associative], info(:merge, 2))

      assert Enum.any?(suggestions, &String.contains?(&1, "associativity"))
      assert Enum.any?(suggestions, &String.contains?(&1, "MyApp.Config.merge("))
    end

    test "is not rendered for a unary function" do
      suggestions = generate([:associative], info(:merge, 1))

      refute Enum.any?(suggestions, &String.contains?(&1, "associativity"))
    end
  end

  describe "commutativity" do
    test "renders f(a, b) == f(b, a) for a binary function" do
      suggestions = generate([:commutative], info(:merge, 2))

      assert Enum.any?(suggestions, &String.contains?(&1, "commutativity"))
    end

    test "is not rendered for a unary function" do
      suggestions = generate([:commutative], info(:merge, 1))

      refute Enum.any?(suggestions, &String.contains?(&1, "commutativity"))
    end
  end

  describe "identity" do
    test "uses the concrete identity value when one is supplied" do
      suggestions = generate([:identity], info(:merge, 2), identity: "%{}")

      assert Enum.any?(suggestions, &String.contains?(&1, "identity = %{}"))
    end

    test "falls back to a TODO placeholder when no identity is known" do
      suggestions = generate([:identity], info(:merge, 2))

      assert Enum.any?(suggestions, &String.contains?(&1, "TODO: replace with the identity"))
    end
  end

  describe "idempotence - arity awareness" do
    test "unary functions get f(f(x)) == f(x)" do
      suggestions = generate([:idempotent], info(:trim, 1))

      assert Enum.any?(suggestions, &String.contains?(&1, "idempotence: f(f(x)) == f(x)"))
    end

    test "binary functions get f(a, a) == a" do
      suggestions = generate([:idempotent], info(:merge, 2))

      assert Enum.any?(suggestions, &String.contains?(&1, "idempotence: f(a, a) == a"))
      refute Enum.any?(suggestions, &String.contains?(&1, "f(f(x))"))
    end

    test "binary idempotence still names the real function" do
      suggestions = generate([:idempotent], info(:merge, 2))

      assert Enum.any?(suggestions, &String.contains?(&1, "MyApp.Config.merge(a, a) == a"))
    end
  end

  describe "involution" do
    test "renders a double-application round-trip" do
      suggestions = generate([:involution], info(:reverse, 1))

      assert Enum.any?(suggestions, &String.contains?(&1, "involution"))
    end
  end

  describe "collection laws" do
    test "length preservation renders a length assertion" do
      suggestions = generate([:length_preserving], info(:map_all, 1))

      assert Enum.any?(suggestions, &String.contains?(&1, "length(result) == length(list)"))
    end

    test "permutation renders a sorted-equality assertion" do
      suggestions = generate([:permutation], info(:shuffle, 1))

      assert Enum.any?(suggestions, &String.contains?(&1, "Enum.sort(result) == Enum.sort(list)"))
    end
  end

  describe "totality" do
    test "renders a no-crash property" do
      suggestions = generate([:total], info(:parse, 1))

      assert Enum.any?(suggestions, &String.contains?(&1, "never raises"))
    end
  end

  describe "library syntax" do
    test "PropEr uses forall" do
      suggestions = generate([:associative], info(:merge, 2), library: :proper)

      assert Enum.any?(suggestions, &String.contains?(&1, "forall"))
      refute Enum.any?(suggestions, &String.contains?(&1, "check all"))
    end

    test "stream_data uses check all" do
      suggestions = generate([:associative], info(:merge, 2), library: :stream_data)

      assert Enum.any?(suggestions, &String.contains?(&1, "check all"))
    end
  end

  describe "edge cases" do
    test "an unknown law produces no suggestion" do
      assert generate([:not_a_law], info(:f, 1)) == []
    end

    test "no laws and no patterns produces no suggestions" do
      assert generate([], info(:f, 1)) == []
    end

    test "laws and patterns are both emitted" do
      suggestions = generate([:associative], info(:merge, 2), patterns: [{:algebraic, "r"}])

      assert Enum.any?(suggestions, &String.contains?(&1, "associativity"))
      assert length(suggestions) > 1
    end

    test "duplicate suggestions are de-duplicated" do
      suggestions = generate([:round_trip], info(:encode, 1), patterns: [{:encoder_decoder, "r"}])

      assert suggestions == Enum.uniq(suggestions)
    end

    test "every suggestion is non-empty formatted code" do
      for law <- [
            :associative,
            :commutative,
            :identity,
            :idempotent,
            :involution,
            :total,
            :permutation,
            :length_preserving
          ],
          suggestion <- generate([law], info(:merge, 2)) do
        assert String.trim(suggestion) != ""
        assert String.contains?(suggestion, "end")
      end
    end
  end
end
