defmodule PropWise.PatternDetectorTest do
  use ExUnit.Case, async: true

  alias PropWise.PatternDetector

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

  describe "detect_patterns/1 - collection operations" do
    test "detects Enum.map usage" do
      func = make_function(quote(do: Enum.map(list, fn x -> x * 2 end)))
      patterns = PatternDetector.detect_patterns(func)
      assert Enum.any?(patterns, fn {type, _} -> type == :collection_operation end)
    end

    test "detects Enum.filter usage" do
      func = make_function(quote(do: Enum.filter(list, &(&1 > 0))))
      patterns = PatternDetector.detect_patterns(func)
      assert Enum.any?(patterns, fn {type, _} -> type == :collection_operation end)
    end

    test "detects list comprehension" do
      func = make_function(quote(do: for(x <- list, do: x * 2)))
      patterns = PatternDetector.detect_patterns(func)
      assert Enum.any?(patterns, fn {type, _} -> type == :collection_operation end)
    end

    test "does not detect simple function calls as collection ops" do
      func = make_function(quote(do: String.upcase(x)))
      patterns = PatternDetector.detect_patterns(func)
      refute Enum.any?(patterns, fn {type, _} -> type == :collection_operation end)
    end
  end

  describe "detect_patterns/1 - transformation" do
    test "detects struct update syntax" do
      func = make_function(quote(do: %{user | name: "new"}))
      patterns = PatternDetector.detect_patterns(func)
      assert Enum.any?(patterns, fn {type, _} -> type == :transformation end)
    end

    test "does NOT detect bare pipeline as transformation" do
      func = make_function(quote(do: x |> String.trim() |> String.upcase()))
      patterns = PatternDetector.detect_patterns(func)
      refute Enum.any?(patterns, fn {type, _} -> type == :transformation end)
    end

    test "does NOT detect bare 'with' as transformation" do
      func =
        make_function(
          quote do
            with {:ok, a} <- fetch(x) do
              fetch(a)
            end
          end
        )

      patterns = PatternDetector.detect_patterns(func)
      refute Enum.any?(patterns, fn {type, _} -> type == :transformation end)
    end
  end

  describe "detect_patterns/1 - validation" do
    test "detects function name ending in ?" do
      func = make_function(quote(do: x > 0), name: :positive?)
      patterns = PatternDetector.detect_patterns(func)

      assert {_, "Boolean predicate"} =
               Enum.find(patterns, fn {type, _} -> type == :validation end)
    end

    test "detects function starting with valid" do
      func = make_function(quote(do: x != nil), name: :validate_email)
      patterns = PatternDetector.detect_patterns(func)
      assert Enum.any?(patterns, fn {type, _} -> type == :validation end)
    end

    test "detects function starting with is_" do
      func = make_function(quote(do: is_binary(x)), name: :is_admin)
      patterns = PatternDetector.detect_patterns(func)

      assert {_, "Type check function"} =
               Enum.find(patterns, fn {type, _} -> type == :validation end)
    end

    test "does NOT detect ordinary functions as validation" do
      func = make_function(quote(do: x + 1), name: :transform)
      patterns = PatternDetector.detect_patterns(func)
      refute Enum.any?(patterns, fn {type, _} -> type == :validation end)
    end

    test "does NOT flag functions that merely USE booleans internally" do
      func =
        make_function(
          quote do
            if x > 0, do: x, else: -x
          end,
          name: :absolute_value
        )

      patterns = PatternDetector.detect_patterns(func)
      refute Enum.any?(patterns, fn {type, _} -> type == :validation end)
    end
  end

  describe "detect_patterns/1 - numeric" do
    test "detects :math module calls" do
      func = make_function(quote(do: :math.sqrt(x)))
      patterns = PatternDetector.detect_patterns(func)
      assert Enum.any?(patterns, fn {type, _} -> type == :numeric end)
    end

    test "detects kernel numeric functions" do
      func = make_function(quote(do: div(x, y)))
      patterns = PatternDetector.detect_patterns(func)
      assert Enum.any?(patterns, fn {type, _} -> type == :numeric end)
    end

    test "detects significant arithmetic (2+ operations)" do
      func = make_function(quote(do: (a + b) * c))
      patterns = PatternDetector.detect_patterns(func)
      assert Enum.any?(patterns, fn {type, _} -> type == :numeric end)
    end

    test "does NOT flag single arithmetic operation" do
      func = make_function(quote(do: x + 1))
      patterns = PatternDetector.detect_patterns(func)
      refute Enum.any?(patterns, fn {type, _} -> type == :numeric end)
    end

    test "does NOT flag pipes or arrows as arithmetic" do
      func = make_function(quote(do: list |> Enum.map(fn x -> x end)))
      patterns = PatternDetector.detect_patterns(func)
      refute Enum.any?(patterns, fn {type, _} -> type == :numeric end)
    end
  end

  describe "detect_patterns/1 - algebraic" do
    test "detects merge in function name" do
      func = make_function(quote(do: Map.merge(a, b)), name: :merge_configs)
      patterns = PatternDetector.detect_patterns(func)
      assert Enum.any?(patterns, fn {type, _} -> type == :algebraic end)
    end

    test "does NOT match substring 'add' in non-algebraic context" do
      # "add" was removed from algebraic operations list
      func = make_function(quote(do: [x | list]), name: :add_item)
      patterns = PatternDetector.detect_patterns(func)
      refute Enum.any?(patterns, fn {type, _} -> type == :algebraic end)
    end
  end

  describe "detect_patterns/1 - encoder/decoder" do
    test "detects encode in function name segments" do
      func = make_function(quote(do: Jason.encode!(data)), name: :encode_json)
      patterns = PatternDetector.detect_patterns(func)
      assert Enum.any?(patterns, fn {type, _} -> type == :encoder_decoder end)
    end

    test "does NOT match encoder as substring" do
      func = make_function(quote(do: x), name: :encoder_config)
      patterns = PatternDetector.detect_patterns(func)
      # "encoder" splits into ["encoder", "config"], "encode" is not in segments
      refute Enum.any?(patterns, fn {type, _} -> type == :encoder_decoder end)
    end
  end

  describe "detect_patterns/1 - parser" do
    test "detects parse in function name segments" do
      func = make_function(quote(do: String.split(input, ",")), name: :parse_csv)
      patterns = PatternDetector.detect_patterns(func)
      assert Enum.any?(patterns, fn {type, _} -> type == :parser end)
    end

    test "does NOT match parser as substring" do
      # "parser" splits into ["parser"], "parse" is not in segments
      func = make_function(quote(do: x), name: :parser_config)
      patterns = PatternDetector.detect_patterns(func)
      refute Enum.any?(patterns, fn {type, _} -> type == :parser end)
    end
  end

  describe "find_inverse_pairs/1" do
    test "finds encode/decode pair in same module" do
      functions = [
        make_function(quote(do: x), name: :encode, module: "Codec"),
        make_function(quote(do: x), name: :decode, module: "Codec")
      ]

      pairs = PatternDetector.find_inverse_pairs(functions)
      assert [_] = pairs
    end

    test "finds to_/from_ prefix pairs" do
      functions = [
        make_function(quote(do: x), name: :to_string, module: "Converter"),
        make_function(quote(do: x), name: :from_string, module: "Converter")
      ]

      pairs = PatternDetector.find_inverse_pairs(functions)
      assert [_] = pairs
    end

    test "does NOT match across different modules" do
      functions = [
        make_function(quote(do: x), name: :encode, module: "ModuleA"),
        make_function(quote(do: x), name: :decode, module: "ModuleB")
      ]

      pairs = PatternDetector.find_inverse_pairs(functions)
      assert [] = pairs
    end

    test "does NOT produce false positive: transformation vs format" do
      functions = [
        make_function(quote(do: x), name: :detect_parser, module: "Detector"),
        make_function(quote(do: x), name: :detect_transformation, module: "Detector")
      ]

      pairs = PatternDetector.find_inverse_pairs(functions)
      assert [] = pairs
    end

    test "does NOT produce false positive: substring matches" do
      functions = [
        make_function(quote(do: x), name: :reformat_data, module: "Utils"),
        make_function(quote(do: x), name: :parse_input, module: "Utils")
      ]

      pairs = PatternDetector.find_inverse_pairs(functions)
      assert [] = pairs
    end
  end
end
