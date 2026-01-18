defmodule PropWise.ParserTest do
  use ExUnit.Case, async: true

  alias PropWise.Parser

  describe "parse_file/1" do
    test "extracts function definitions from valid Elixir code" do
      test_file = "/tmp/propwise_test_#{System.unique_integer([:positive])}.ex"

      File.write!(test_file, """
      defmodule TestModule do
        def public_function(x, y) do
          x + y
        end

        defp private_function(z) do
          z * 2
        end
      end
      """)

      functions = Parser.parse_file(test_file)

      File.rm!(test_file)

      assert [_, _] = functions
      assert Enum.any?(functions, fn f -> f.name == :public_function and f.arity == 2 end)
      assert Enum.any?(functions, fn f -> f.name == :private_function and f.arity == 1 end)
    end

    test "returns empty list for non-existent file" do
      assert [] = Parser.parse_file("/nonexistent/file.ex")
    end
  end
end
