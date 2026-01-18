defmodule PropWise.PurityAnalyzerTest do
  use ExUnit.Case, async: true

  alias PropWise.PurityAnalyzer

  describe "analyze/1" do
    test "detects pure functions" do
      function_info = %{
        body:
          quote do
            x + y
          end
      }

      assert {:pure, []} = PurityAnalyzer.analyze(function_info)
    end

    test "detects IO side effects" do
      function_info = %{
        body:
          quote do
            IO.puts("hello")
          end
      }

      assert {:impure, side_effects} = PurityAnalyzer.analyze(function_info)
      assert match?([{:module_call, IO, :puts, 1}], side_effects)
    end

    test "detects File side effects" do
      function_info = %{
        body:
          quote do
            File.read!("test.txt")
          end
      }

      assert {:impure, side_effects} = PurityAnalyzer.analyze(function_info)
      assert match?([{:module_call, File, :read!, 1}], side_effects)
    end

    test "detects GenServer side effects" do
      function_info = %{
        body:
          quote do
            GenServer.call(pid, :message)
          end
      }

      assert {:impure, side_effects} = PurityAnalyzer.analyze(function_info)
      assert match?([{:module_call, GenServer, :call, 2}], side_effects)
    end
  end

  describe "pure?/1" do
    test "returns true for pure functions" do
      function_info = %{
        body:
          quote do
            Enum.map([1, 2, 3], fn x -> x * 2 end)
          end
      }

      assert PurityAnalyzer.pure?(function_info)
    end

    test "returns false for impure functions" do
      function_info = %{
        body:
          quote do
            IO.inspect(value)
          end
      }

      refute PurityAnalyzer.pure?(function_info)
    end
  end
end
