defmodule PropWise.SuggestionGeneratorTest do
  use ExUnit.Case, async: true

  alias PropWise.SuggestionGenerator

  defp make_function(opts) do
    %{
      module: Keyword.get(opts, :module, "MyApp.Utils"),
      name: Keyword.get(opts, :name, :transform),
      arity: Keyword.get(opts, :arity, 1),
      args: [],
      body: quote(do: nil),
      file: "test.ex",
      line: 1,
      type: :public
    }
  end

  describe "generate/3 - arity awareness" do
    test "single-arity function uses single argument" do
      func = make_function(name: :process, arity: 1)

      suggestions =
        SuggestionGenerator.generate([{:transformation, "reason"}], func, :stream_data)

      assert Enum.any?(suggestions, &String.contains?(&1, "Utils.process(input)"))
    end

    test "two-arity function uses two arguments" do
      func = make_function(name: :merge, arity: 2)

      suggestions =
        SuggestionGenerator.generate([{:transformation, "reason"}], func, :stream_data)

      assert Enum.any?(suggestions, &String.contains?(&1, "Utils.merge(a, b)"))
    end

    test "three-arity function uses three arguments" do
      func = make_function(name: :combine, arity: 3)

      suggestions =
        SuggestionGenerator.generate([{:transformation, "reason"}], func, :stream_data)

      assert Enum.any?(suggestions, &String.contains?(&1, "Utils.combine(a, b, c)"))
    end
  end

  describe "generate/3 - library syntax" do
    test "stream_data uses 'check all' syntax" do
      func = make_function(name: :valid?, arity: 1)
      suggestions = SuggestionGenerator.generate([{:validation, "reason"}], func, :stream_data)

      assert Enum.any?(suggestions, &String.contains?(&1, "check all"))
    end

    test "proper uses 'forall' syntax" do
      func = make_function(name: :valid?, arity: 1)
      suggestions = SuggestionGenerator.generate([{:validation, "reason"}], func, :proper)

      assert Enum.any?(suggestions, &String.contains?(&1, "forall"))
    end

    test "stream_data uses 'assert'" do
      func = make_function(name: :valid?, arity: 1)
      suggestions = SuggestionGenerator.generate([{:validation, "reason"}], func, :stream_data)

      assert Enum.any?(suggestions, &String.contains?(&1, "assert"))
    end
  end

  describe "generate/3 - encoder/decoder uses actual function names" do
    test "uses actual function name, not hardcoded encode/decode" do
      func = make_function(name: :serialize_data, arity: 1)

      suggestions =
        SuggestionGenerator.generate([{:encoder_decoder, "reason"}], func, :stream_data)

      assert Enum.any?(suggestions, &String.contains?(&1, "serialize_data"))
      assert Enum.any?(suggestions, &String.contains?(&1, "deserialize_data"))
      # Should NOT reference generic encode/decode
      refute Enum.any?(suggestions, &String.contains?(&1, "Utils.encode("))
    end

    test "computes inverse name for decode" do
      func = make_function(name: :decode_message, arity: 1)

      suggestions =
        SuggestionGenerator.generate([{:encoder_decoder, "reason"}], func, :stream_data)

      assert Enum.any?(suggestions, &String.contains?(&1, "encode_message"))
    end
  end

  describe "generate/3 - algebraic with correct arity" do
    test "binary function gets associativity/commutativity suggestions" do
      func = make_function(name: :merge, arity: 2)
      suggestions = SuggestionGenerator.generate([{:algebraic, "reason"}], func, :stream_data)

      assert Enum.any?(suggestions, &String.contains?(&1, "associativity"))
      assert Enum.any?(suggestions, &String.contains?(&1, "commutativity"))
    end

    test "non-binary function gets basic suggestion" do
      func = make_function(name: :merge, arity: 1)
      suggestions = SuggestionGenerator.generate([{:algebraic, "reason"}], func, :stream_data)

      refute Enum.any?(suggestions, &String.contains?(&1, "associativity"))
      assert Enum.any?(suggestions, &String.contains?(&1, "deterministic"))
    end
  end

  describe "generate/3 - collection operation" do
    test "includes TODO guidance for invariant" do
      func = make_function(name: :sort_items, arity: 1)

      suggestions =
        SuggestionGenerator.generate([{:collection_operation, "reason"}], func, :stream_data)

      assert Enum.any?(suggestions, &String.contains?(&1, "TODO"))
    end
  end

  describe "generate/3 - parser" do
    test "uses actual function name" do
      func = make_function(name: :parse_json, arity: 1)
      suggestions = SuggestionGenerator.generate([{:parser, "reason"}], func, :stream_data)

      assert Enum.any?(suggestions, &String.contains?(&1, "Utils.parse_json(input)"))
      # Should NOT reference Module.format that doesn't exist
      refute Enum.any?(suggestions, &String.contains?(&1, "Utils.format("))
    end
  end
end
