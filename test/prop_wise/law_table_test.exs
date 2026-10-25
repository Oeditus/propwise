defmodule PropWise.LawTableTest do
  @moduledoc """
  Tests for the law-inference table.

  Acceptance criterion: `Map.merge` must be inferred as associative, and the
  table must be queryable and extensible.
  """

  use ExUnit.Case, async: true

  alias PropWise.LawTable

  describe "laws_for_call/1 - the acceptance case" do
    test "Map.merge is inferred as associative" do
      laws = LawTable.laws_for_call("Map.merge")

      assert :associative in laws
    end

    test "Map.merge also implies idempotence and an identity element" do
      laws = LawTable.laws_for_call("Map.merge")

      assert :idempotent in laws
      assert :identity in laws
    end

    test "Map.merge has a concrete identity value" do
      assert LawTable.identity_for("Map.merge") == "%{}"
    end
  end

  describe "laws_for_call/1 - other entries" do
    test "Enum.reverse is an involution and a permutation" do
      laws = LawTable.laws_for_call("Enum.reverse")

      assert :involution in laws
      assert :permutation in laws
      assert :length_preserving in laws
    end

    test "Enum.sort is idempotent, length preserving and monotonic" do
      laws = LawTable.laws_for_call("Enum.sort")

      assert :idempotent in laws
      assert :length_preserving in laws
      assert :monotonic in laws
    end

    test "String.trim is idempotent" do
      assert :idempotent in LawTable.laws_for_call("String.trim")
    end

    test "Base.encode64 implies a round-trip" do
      assert :round_trip in LawTable.laws_for_call("Base.encode64")
    end

    test "MapSet.union is commutative and associative" do
      laws = LawTable.laws_for_call("MapSet.union")

      assert :commutative in laws
      assert :associative in laws
    end

    test "abs is idempotent and monotonic" do
      laws = LawTable.laws_for_call("abs")

      assert :idempotent in laws
      assert :monotonic in laws
    end
  end

  describe "laws_for_call/1 - edge cases" do
    test "an unknown call yields no laws" do
      assert LawTable.laws_for_call("Totally.Unknown.thing") == []
    end

    test "an empty call name yields no laws" do
      assert LawTable.laws_for_call("") == []
    end

    test "matching is tolerant of a leading colon" do
      assert LawTable.laws_for_call("math.sqrt") == LawTable.laws_for_call(":math.sqrt")
    end

    test "a partial name does not match" do
      assert LawTable.laws_for_call("Map") == []
      assert LawTable.laws_for_call("merge") == []
    end
  end

  describe "laws_for_calls/1" do
    test "unions the laws of every known call" do
      laws = LawTable.laws_for_calls(["Map.merge", "Enum.reverse"])

      assert :associative in laws
      assert :involution in laws
    end

    test "de-duplicates repeated laws" do
      laws = LawTable.laws_for_calls(["Map.merge", "Map.put"])

      assert Enum.count(laws, &(&1 == :idempotent)) == 1
    end

    test "returns [] for an empty list" do
      assert LawTable.laws_for_calls([]) == []
    end

    test "returns [] when no call is known" do
      assert LawTable.laws_for_calls(["Nope.a", "Nope.b"]) == []
    end
  end

  describe "identity_for/1" do
    test "returns the identity for known operations" do
      assert LawTable.identity_for("Enum.sum") == "0"
      assert LawTable.identity_for("Enum.concat") == "[]"
    end

    test "returns nil when no identity is known" do
      assert LawTable.identity_for("Enum.reverse") == nil
      assert LawTable.identity_for("Unknown.thing") == nil
    end
  end

  describe "known_calls/0 - table integrity" do
    test "every entry declares at least one law" do
      for call <- LawTable.known_calls() do
        assert LawTable.laws_for_call(call) != [], "no laws for #{call}"
      end
    end

    test "every declared law is part of the documented vocabulary" do
      vocabulary = [
        :involution,
        :idempotent,
        :associative,
        :commutative,
        :identity,
        :permutation,
        :length_preserving,
        :monotonic,
        :round_trip,
        :total,
        :bounded,
        :deterministic
      ]

      for call <- LawTable.known_calls(),
          law <- LawTable.laws_for_call(call) do
        assert law in vocabulary, "#{call} declares undocumented law #{inspect(law)}"
      end
    end

    test "call names are unique" do
      calls = LawTable.known_calls()
      assert calls == Enum.uniq(calls)
    end

    test "the table is non-trivial" do
      assert length(LawTable.known_calls()) > 40
    end
  end
end
