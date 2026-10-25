defmodule PropWise.LawTable do
  @moduledoc """
  Infers property-test *laws* from the functions a body actually calls.

  Pattern detection answers "is this worth testing?". The law table answers the
  much more useful question: **which property should I write?**

  Given a function that calls `Map.merge/3`, the honest suggestion is
  associativity and idempotence — not the generic "deterministic output" that
  applies to literally any pure function. The table encodes that knowledge:

      iex> PropWise.LawTable.laws_for_calls(["Map.merge"])
      [:idempotent, :associative, :identity]

  ## Law vocabulary

  | Law | Meaning |
  | --- | --- |
  | `:involution` | `f(f(x)) == x` |
  | `:idempotent` | `f(f(x)) == f(x)` |
  | `:associative` | `f(f(a, b), c) == f(a, f(b, c))` |
  | `:commutative` | `f(a, b) == f(b, a)` |
  | `:identity` | `f(a, identity) == a` for some known identity |
  | `:permutation` | output is a permutation of input |
  | `:length_preserving` | `length(f(x)) == length(x)` |
  | `:monotonic` | `a <= b implies f(a) <= f(b)` |
  | `:round_trip` | paired with the inverse function |
  | `:total` | never raises for generated input |
  | `:bounded` | output stays within a known range |
  | `:deterministic` | `f(x) == f(x)` — the weakest law, used as a fallback |

  ## Adding entries

  Entries are matched against the *call name as written in the source*
  (`"Map.merge"`), which is what the MetaAST records. Add a row to
  `@table`; the first matching entry wins.
  """

  @typedoc "A property law name."
  @type law ::
          :involution
          | :idempotent
          | :associative
          | :commutative
          | :identity
          | :permutation
          | :length_preserving
          | :monotonic
          | :round_trip
          | :total
          | :bounded
          | :deterministic

  # Ordered: the first matching entry wins. `:laws` lists every law the call
  # supports; `:identity` carries a concrete identity value when one is obvious.
  @table [
    # --- Maps -----------------------------------------------------------------
    {"Map.merge", laws: [:idempotent, :associative, :identity], identity: "%{}"},
    {"Map.put", laws: [:idempotent, :associative]},
    {"Map.put_new", laws: [:idempotent]},
    {"Map.update", laws: [:idempotent]},
    {"Map.delete", laws: [:idempotent]},
    {"Map.drop", laws: [:idempotent]},
    {"Map.take", laws: [:idempotent]},
    {"Map.keys", laws: [:length_preserving, :deterministic]},
    {"Map.values", laws: [:length_preserving, :deterministic]},
    {"Map.to_list", laws: [:length_preserving, :round_trip]},
    {"Map.new", laws: [:idempotent]},
    # --- Collections ----------------------------------------------------------
    {"Enum.reverse", laws: [:involution, :length_preserving, :permutation]},
    {"Enum.sort", laws: [:idempotent, :length_preserving, :permutation, :monotonic]},
    {"Enum.sort_by", laws: [:idempotent, :length_preserving, :permutation]},
    {"Enum.uniq", laws: [:idempotent]},
    {"Enum.dedup", laws: [:idempotent]},
    {"Enum.map", laws: [:length_preserving]},
    {"Enum.filter", laws: [:total]},
    {"Enum.reject", laws: [:total]},
    {"Enum.flat_map", laws: [:total]},
    {"Enum.take", laws: [:total]},
    {"Enum.drop", laws: [:total]},
    {"Enum.chunk_every", laws: [:total]},
    {"Enum.group_by", laws: [:total]},
    {"Enum.frequencies", laws: [:total]},
    {"Enum.sum", laws: [:commutative, :associative, :identity], identity: "0"},
    {"Enum.concat", laws: [:associative, :identity], identity: "[]"},
    {"Enum.join", laws: [:total]},
    {"Enum.at", laws: [:total]},
    {"Enum.zip", laws: [:length_preserving]},
    {"List.flatten", laws: [:idempotent]},
    {"List.wrap", laws: [:idempotent]},
    {"List.duplicate", laws: [:total]},
    {"List.to_string", laws: [:total]},
    {"MapSet.union",
     laws: [:idempotent, :associative, :commutative, :identity], identity: "MapSet.new()"},
    {"MapSet.intersection", laws: [:idempotent, :associative, :commutative]},
    {"MapSet.difference", laws: [:idempotent]},
    {"MapSet.new", laws: [:idempotent]},
    # --- Strings --------------------------------------------------------------
    {"String.split", laws: [:round_trip]},
    {"String.trim", laws: [:idempotent]},
    {"String.downcase", laws: [:idempotent]},
    {"String.upcase", laws: [:idempotent]},
    {"String.reverse", laws: [:involution]},
    {"String.replace", laws: [:idempotent]},
    {"String.to_charlist", laws: [:round_trip]},
    {"String.length", laws: [:total]},
    {"String.slice", laws: [:total]},
    {"String.pad_leading", laws: [:total]},
    {"String.pad_trailing", laws: [:total]},
    {"String.duplicate", laws: [:total]},
    {"String.replace_prefix", laws: [:idempotent]},
    {"String.replace_suffix", laws: [:idempotent]},
    # --- Numeric --------------------------------------------------------------
    {"abs", laws: [:idempotent, :monotonic]},
    {"div", laws: [:total]},
    {"rem", laws: [:bounded, :total]},
    {"round", laws: [:idempotent, :monotonic]},
    {"trunc", laws: [:idempotent, :monotonic]},
    {"floor", laws: [:idempotent, :monotonic]},
    {"ceil", laws: [:idempotent, :monotonic]},
    {"min", laws: [:idempotent, :associative, :commutative]},
    {"max", laws: [:idempotent, :associative, :commutative]},
    {"math.sqrt", laws: [:monotonic]},
    {"math.pow", laws: [:total]},
    {"math.log", laws: [:total]},
    # --- Encoding -------------------------------------------------------------
    {"Base.encode64", laws: [:round_trip]},
    {"Base.decode64", laws: [:round_trip]},
    {"Base.encode16", laws: [:round_trip]},
    {"Base.decode16", laws: [:round_trip]},
    {"Base.url_encode64", laws: [:round_trip]},
    {"Base.url_decode64", laws: [:round_trip]},
    {"Jason.encode", laws: [:round_trip]},
    {"Jason.decode", laws: [:round_trip]},
    {"URI.encode", laws: [:round_trip]},
    {"URI.decode", laws: [:round_trip]},
    {":erlang.term_to_binary", laws: [:round_trip]},
    {":erlang.binary_to_term", laws: [:round_trip]},
    {"Integer.to_string", laws: [:round_trip]},
    {"Integer.parse", laws: [:round_trip]},
    {"Float.to_string", laws: [:round_trip]},
    {"Float.parse", laws: [:round_trip]},
    {"String.to_integer", laws: [:round_trip]},
    {"String.to_float", laws: [:round_trip]}
  ]

  @doc """
  Returns the laws implied by a set of call names found in a function body.

  Call names are matched against the table; unknown calls contribute nothing.
  The result is de-duplicated and ordered by the table.

      iex> PropWise.LawTable.laws_for_calls(["Enum.reverse"])
      [:involution, :length_preserving, :permutation]

      iex> PropWise.LawTable.laws_for_calls(["Something.unknown"])
      []

  """
  @spec laws_for_calls([String.t()]) :: [law()]
  def laws_for_calls(call_names) when is_list(call_names) do
    call_names
    |> Enum.flat_map(&laws_for_call/1)
    |> Enum.uniq()
  end

  @doc """
  Returns the laws implied by a single call name.
  """
  @spec laws_for_call(String.t()) :: [law()]
  def laws_for_call(call_name) when is_binary(call_name) do
    case lookup(call_name) do
      nil -> []
      entry -> Keyword.get(entry, :laws, [])
    end
  end

  @doc """
  Returns the concrete identity element for a call name, if the table knows one.

      iex> PropWise.LawTable.identity_for("Map.merge")
      "%{}"

      iex> PropWise.LawTable.identity_for("Enum.reverse")
      nil

  """
  @spec identity_for(String.t()) :: String.t() | nil
  def identity_for(call_name) when is_binary(call_name) do
    case lookup(call_name) do
      nil -> nil
      entry -> Keyword.get(entry, :identity)
    end
  end

  @doc """
  Returns every call name known to the table. Useful for documentation and
  for testing that the table stays well-formed.
  """
  @spec known_calls() :: [String.t()]
  def known_calls, do: Enum.map(@table, fn {name, _opts} -> name end)

  # Exact match first, then a tolerant match that ignores a leading `:`
  # (Elixir writes `:math.sqrt` in source but `math.sqrt` in the MetaAST).
  defp lookup(call_name) do
    Enum.find_value(@table, fn {name, opts} ->
      if name == call_name or
           String.trim_leading(name, ":") == String.trim_leading(call_name, ":") do
        opts
      end
    end)
  end
end
