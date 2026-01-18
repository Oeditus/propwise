defmodule PropWiseTest do
  use ExUnit.Case
  doctest PropWise

  test "analyze returns a map with expected keys" do
    # Create a temporary test project
    test_dir = "/tmp/propwise_test_#{System.unique_integer([:positive])}"
    File.mkdir_p!(test_dir)

    File.write!(Path.join(test_dir, "test.ex"), """
    defmodule Test do
      def pure_func(x), do: x * 2
    end
    """)

    result = PropWise.analyze(test_dir, min_score: 0)

    File.rm_rf!(test_dir)

    assert is_map(result)
    assert Map.has_key?(result, :candidates)
    assert Map.has_key?(result, :inverse_pairs)
    assert Map.has_key?(result, :total_functions)
    assert Map.has_key?(result, :candidates_count)
  end
end
