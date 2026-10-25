defmodule PropWise.PropertyTest do
  @moduledoc """
  Property-based tests for PropWise's own pure functions.

  These exercise the invariants that the unit tests only sample:
  `find_inverse_pairs/1` and the ranking/serialisation pipeline.
  """

  use ExUnit.Case, async: true

  use ExUnitProperties

  alias PropWise.PatternDetector

  @inverse_names [
    {:encode, :decode},
    {:serialize, :deserialize},
    {:compress, :decompress},
    {:encrypt, :decrypt},
    {:pack, :unpack},
    {:marshal, :unmarshal}
  ]

  defp function_info(module, name, arity) do
    %{
      module: module,
      name: name,
      arity: arity,
      args: [],
      body: quote(do: nil),
      file: "lib/x.ex",
      line: 1,
      type: :public
    }
  end

  property "every detected pair joins two distinct functions in one module" do
    check all(
            module <- member_of(["A", "B", "C"]),
            {forward, inverse} <- member_of(@inverse_names)
          ) do
      functions = [
        function_info(module, forward, 1),
        function_info(module, inverse, 1)
      ]

      pairs = PatternDetector.find_inverse_pairs(functions)

      assert pairs != [], "expected a pair for #{forward}/#{inverse}"

      for pair <- pairs do
        {mod, fwd_name, _} = pair.forward
        {mod2, inv_name, _} = pair.inverse

        assert mod == mod2
        assert fwd_name != inv_name
      end
    end
  end

  property "no pair is ever reported twice" do
    check all(
            module <- member_of(["A", "B"]),
            {forward, inverse} <- member_of(@inverse_names)
          ) do
      functions = [
        function_info(module, forward, 1),
        function_info(module, inverse, 1)
      ]

      pairs = PatternDetector.find_inverse_pairs(functions)
      keys = Enum.map(pairs, &{&1.forward, &1.inverse})

      assert keys == Enum.uniq(keys)
    end
  end

  property "inverse-pair detection never crosses module boundaries" do
    check all(
            {forward, inverse} <- member_of(@inverse_names),
            m1 <- member_of(["A", "B"]),
            m2 <- member_of(["C", "D"])
          ) do
      functions = [
        function_info(m1, forward, 1),
        function_info(m2, inverse, 1)
      ]

      assert PatternDetector.find_inverse_pairs(functions) == []
    end
  end

  property "detect_patterns/1 is total: any body yields a list of {atom, binary}" do
    check all(body <- term()) do
      info = function_info("M", :f, 1) |> Map.put(:body, body)

      patterns = PatternDetector.detect_patterns(info)

      assert is_list(patterns)

      for {type, reason} <- patterns do
        assert is_atom(type)
        assert is_binary(reason)
      end
    end
  end
end
