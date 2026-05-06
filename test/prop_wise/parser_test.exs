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

  describe "parse_project/2 umbrella support" do
    setup do
      base = "/tmp/propwise_umbrella_#{System.unique_integer([:positive])}"
      app_lib = Path.join([base, "apps", "my_app", "lib"])
      File.mkdir_p!(app_lib)

      File.write!(Path.join(app_lib, "my_mod.ex"), """
      defmodule MyApp.MyMod do
        def greet(name), do: "Hello, " <> name
      end
      """)

      on_exit(fn -> File.rm_rf!(base) end)
      %{base: base}
    end

    test "auto-detects umbrella project when no lib/ at root", %{base: base} do
      functions = Parser.parse_project(base)
      assert [%{name: :greet, module: "MyApp.MyMod"}] = functions
    end

    test "prefers lib/ when both lib/ and apps/ exist", %{base: base} do
      lib_path = Path.join(base, "lib")
      File.mkdir_p!(lib_path)

      File.write!(Path.join(lib_path, "root_mod.ex"), """
      defmodule RootMod do
        def root_fn(x), do: x
      end
      """)

      functions = Parser.parse_project(base)
      assert [%{name: :root_fn, module: "RootMod"}] = functions
    end

    test "respects explicit analyze_paths over umbrella detection", %{base: base} do
      functions = Parser.parse_project(base, analyze_paths: ["apps/my_app/lib"])
      assert [%{name: :greet}] = functions
    end
  end
end
