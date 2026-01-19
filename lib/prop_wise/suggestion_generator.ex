defmodule PropWise.SuggestionGenerator do
  @moduledoc """
  Generates property-based testing suggestions for different libraries.
  Supports stream_data and PropEr.
  """

  @doc """
  Generates testing suggestions based on detected patterns and library.
  """
  def generate(patterns, function_info, library) do
    func_name = function_info.name
    module_name = function_info.module |> String.split(".") |> List.last()

    patterns
    |> Enum.flat_map(fn {type, _reason} ->
      generate_for_pattern(type, module_name, func_name, library)
    end)
    |> Enum.uniq()
  end

  defp generate_for_pattern(:collection_operation, module_name, func_name, :stream_data) do
    [
      """
      property "preserves input size" do
        check all list <- list_of(term()) do
          assert length(#{module_name}.#{func_name}(list)) == length(list)
        end
      end
      """,
      """
      property "contains all original elements" do
        check all list <- list_of(term()) do
          result = #{module_name}.#{func_name}(list)
          assert Enum.all?(list, &(&1 in result))
        end
      end
      """
    ]
  end

  defp generate_for_pattern(:collection_operation, module_name, func_name, :proper) do
    [
      """
      property "preserves input size" do
        forall list <- list(term()) do
          length(#{module_name}.#{func_name}(list)) == length(list)
        end
      end
      """,
      """
      property "contains all original elements" do
        forall list <- list(term()) do
          result = #{module_name}.#{func_name}(list)
          Enum.all?(list, &(&1 in result))
        end
      end
      """
    ]
  end

  defp generate_for_pattern(:transformation, module_name, func_name, :stream_data) do
    [
      """
      property "maintains structural invariants" do
        check all input <- term() do
          result = #{module_name}.#{func_name}(input)
          # Add your invariant checks here
          assert valid_structure?(result)
        end
      end
      """,
      """
      property "handles edge cases" do
        check all input <- one_of([constant(nil), constant([]), constant(%{}), term()]) do
          result = #{module_name}.#{func_name}(input)
          assert is_valid_result?(result)
        end
      end
      """
    ]
  end

  defp generate_for_pattern(:transformation, module_name, func_name, :proper) do
    [
      """
      property "maintains structural invariants" do
        forall input <- term() do
          result = #{module_name}.#{func_name}(input)
          # Add your invariant checks here
          valid_structure?(result)
        end
      end
      """,
      """
      property "handles edge cases" do
        forall input <- oneof([nil, [], %{}, term()]) do
          result = #{module_name}.#{func_name}(input)
          is_valid_result?(result)
        end
      end
      """
    ]
  end

  defp generate_for_pattern(:validation, module_name, func_name, :stream_data) do
    [
      """
      property "consistent validation results" do
        check all input <- term() do
          result1 = #{module_name}.#{func_name}(input)
          result2 = #{module_name}.#{func_name}(input)
          assert result1 == result2
        end
      end
      """,
      """
      property "boolean return type" do
        check all input <- term() do
          result = #{module_name}.#{func_name}(input)
          assert is_boolean(result)
        end
      end
      """
    ]
  end

  defp generate_for_pattern(:validation, module_name, func_name, :proper) do
    [
      """
      property "consistent validation results" do
        forall input <- term() do
          result1 = #{module_name}.#{func_name}(input)
          result2 = #{module_name}.#{func_name}(input)
          result1 == result2
        end
      end
      """,
      """
      property "boolean return type" do
        forall input <- term() do
          result = #{module_name}.#{func_name}(input)
          is_boolean(result)
        end
      end
      """
    ]
  end

  defp generate_for_pattern(:algebraic, module_name, func_name, :stream_data) do
    [
      """
      property "associativity" do
        check all a <- term(), b <- term(), c <- term() do
          assert #{module_name}.#{func_name}(#{module_name}.#{func_name}(a, b), c) ==
                 #{module_name}.#{func_name}(a, #{module_name}.#{func_name}(b, c))
        end
      end
      """,
      """
      property "commutativity" do
        check all a <- term(), b <- term() do
          assert #{module_name}.#{func_name}(a, b) == #{module_name}.#{func_name}(b, a)
        end
      end
      """,
      """
      property "identity element" do
        check all a <- term() do
          identity = identity_value()
          assert #{module_name}.#{func_name}(a, identity) == a
        end
      end
      """
    ]
  end

  defp generate_for_pattern(:algebraic, module_name, func_name, :proper) do
    [
      """
      property "associativity" do
        forall {a, b, c} <- {term(), term(), term()} do
          #{module_name}.#{func_name}(#{module_name}.#{func_name}(a, b), c) ==
            #{module_name}.#{func_name}(a, #{module_name}.#{func_name}(b, c))
        end
      end
      """,
      """
      property "commutativity" do
        forall {a, b} <- {term(), term()} do
          #{module_name}.#{func_name}(a, b) == #{module_name}.#{func_name}(b, a)
        end
      end
      """,
      """
      property "identity element" do
        forall a <- term() do
          identity = identity_value()
          #{module_name}.#{func_name}(a, identity) == a
        end
      end
      """
    ]
  end

  defp generate_for_pattern(:encoder_decoder, module_name, _func_name, :stream_data) do
    [
      """
      property "encode/decode round-trip" do
        check all data <- term() do
          encoded = #{module_name}.encode(data)
          assert #{module_name}.decode(encoded) == {:ok, data}
        end
      end
      """,
      """
      property "decode handles invalid input" do
        check all invalid <- binary() do
          case #{module_name}.decode(invalid) do
            {:ok, _} -> true
            {:error, _} -> true
            _ -> false
          end
        end
      end
      """
    ]
  end

  defp generate_for_pattern(:encoder_decoder, module_name, _func_name, :proper) do
    [
      """
      property "encode/decode round-trip" do
        forall data <- term() do
          encoded = #{module_name}.encode(data)
          #{module_name}.decode(encoded) == {:ok, data}
        end
      end
      """,
      """
      property "decode handles invalid input" do
        forall invalid <- binary() do
          case #{module_name}.decode(invalid) do
            {:ok, _} -> true
            {:error, _} -> true
            _ -> false
          end
        end
      end
      """
    ]
  end

  defp generate_for_pattern(:parser, module_name, func_name, :stream_data) do
    [
      """
      property "parse returns expected structure" do
        check all input <- string(:alphanumeric) do
          case #{module_name}.#{func_name}(input) do
            {:ok, result} -> assert valid_parsed_structure?(result)
            {:error, _} -> true
          end
        end
      end
      """,
      """
      property "parse/format round-trip" do
        check all data <- valid_data_generator() do
          formatted = #{module_name}.format(data)
          assert #{module_name}.#{func_name}(formatted) == {:ok, data}
        end
      end
      """
    ]
  end

  defp generate_for_pattern(:parser, module_name, func_name, :proper) do
    [
      """
      property "parse returns expected structure" do
        forall input <- list(range(?a, ?z)) do
          case #{module_name}.#{func_name}(to_string(input)) do
            {:ok, result} -> valid_parsed_structure?(result)
            {:error, _} -> true
          end
        end
      end
      """,
      """
      property "parse/format round-trip" do
        forall data <- valid_data_generator() do
          formatted = #{module_name}.format(data)
          #{module_name}.#{func_name}(formatted) == {:ok, data}
        end
      end
      """
    ]
  end

  defp generate_for_pattern(:numeric, module_name, func_name, :stream_data) do
    [
      """
      property "handles numeric boundaries" do
        check all n <- one_of([integer(), float()]) do
          result = #{module_name}.#{func_name}(n)
          assert is_number(result)
        end
      end
      """,
      """
      property "handles special numeric values" do
        check all n <- member_of([0, -1, 1, :math.pi(), -:math.pi()]) do
          result = #{module_name}.#{func_name}(n)
          assert is_valid_numeric?(result)
        end
      end
      """
    ]
  end

  defp generate_for_pattern(:numeric, module_name, func_name, :proper) do
    [
      """
      property "handles numeric boundaries" do
        forall n <- oneof([integer(), float()]) do
          result = #{module_name}.#{func_name}(n)
          is_number(result)
        end
      end
      """,
      """
      property "handles special numeric values" do
        forall n <- oneof([0, -1, 1]) do
          result = #{module_name}.#{func_name}(n)
          is_valid_numeric?(result)
        end
      end
      """
    ]
  end

  defp generate_for_pattern(_type, _module_name, _func_name, _library), do: []
end
