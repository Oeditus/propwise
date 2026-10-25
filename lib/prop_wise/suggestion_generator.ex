defmodule PropWise.SuggestionGenerator do
  @moduledoc """
  Generates property-based testing suggestions for different libraries.

  Uses a template-based approach where library-specific syntax (stream_data vs PropEr)
  is parameterized, and function name/arity are used to generate accurate call sites.

  ## Law-driven suggestions

  When `PropWise.LawTable` has inferred concrete laws for a function (e.g.
  `Enum.reverse` implies `:involution`), those laws are rendered as real
  properties — `reverse(reverse(x)) == x` — instead of the generic
  "deterministic output" fallback. Pattern-based suggestions are still emitted
  for anything the law table does not cover.
  """

  alias PropWise.LawTable

  @doc """
  Generates testing suggestions based on detected patterns and library.

  `laws` is an optional list of `t:PropWise.LawTable.law/0` values; when given,
  law-specific properties are emitted first.
  """
  @spec generate(
          [PropWise.Candidate.pattern()],
          PropWise.FunctionInfo.t() | map(),
          atom(),
          [LawTable.law()],
          String.t() | nil
        ) :: [String.t()]
  def generate(patterns, function_info, library, laws \\ [], identity \\ nil) do
    ctx = Map.put(build_context(function_info, library), :identity, identity)

    law_suggestions =
      laws
      |> Enum.flat_map(&generate_for_law(&1, ctx))

    pattern_suggestions =
      patterns
      |> Enum.flat_map(fn {type, _reason} ->
        generate_for_pattern(type, ctx)
      end)

    (law_suggestions ++ pattern_suggestions)
    |> Enum.uniq()
  end

  defp build_context(function_info, library) do
    # Use the *full* module name so generated calls resolve without an alias.
    # `MyApp.Deep.Nested.Encoder` must not be truncated to `Encoder`.
    module_name = function_info.module
    func_name = function_info.name
    arity = function_info.arity

    %{
      module: module_name,
      func: func_name,
      arity: arity,
      call: format_call(module_name, func_name, arg_names(arity)),
      library: library
    }
  end

  defp arg_names(0), do: []
  defp arg_names(1), do: ["input"]
  defp arg_names(2), do: ["a", "b"]
  defp arg_names(3), do: ["a", "b", "c"]
  defp arg_names(n) when n > 3, do: Enum.map(1..n, &"arg#{&1}")

  defp format_call(module, func, args) do
    "#{module}.#{func}(#{Enum.join(args, ", ")})"
  end

  # Build a call site structurally (never by string-patching), replacing the
  # first argument with `first_arg` and keeping any remaining arguments.
  defp call_with_first(ctx, first_arg) do
    [_ | rest] = arg_names(ctx.arity)
    format_call(ctx.module, ctx.func, [first_arg | rest])
  end

  # --- Library-specific syntax helpers ---

  defp prop_header(:stream_data, bindings), do: "check all #{bindings} do"
  defp prop_header(:proper, bindings), do: "forall #{bindings} do"

  defp gen_binding(:stream_data, var, gen), do: "#{var} <- #{gen}"
  defp gen_binding(:proper, var, gen), do: "#{var} <- #{gen}"

  defp gen_bindings(:proper, bindings) when length(bindings) > 1 do
    vars = Enum.map_join(bindings, ", ", fn {var, _} -> var end)
    gens = Enum.map_join(bindings, ", ", fn {_, gen} -> gen end)
    "{#{vars}} <- {#{gens}}"
  end

  defp gen_bindings(lib, bindings) do
    Enum.map_join(bindings, ", ", fn {var, gen} -> gen_binding(lib, var, gen) end)
  end

  defp assert_stmt(:stream_data, expr), do: "assert #{expr}"
  defp assert_stmt(:proper, expr), do: expr

  defp gen(:stream_data, :list), do: "list_of(term())"
  defp gen(:stream_data, :string), do: "string(:alphanumeric)"
  defp gen(:stream_data, :binary), do: "binary()"
  defp gen(:stream_data, :number), do: "one_of([integer(), float()])"
  defp gen(:stream_data, :term), do: "term()"

  defp gen(:proper, :list), do: "list(term())"
  defp gen(:proper, :string), do: "list(range(?a, ?z))"
  defp gen(:proper, :binary), do: "binary()"
  defp gen(:proper, :number), do: "oneof([integer(), float()])"
  defp gen(:proper, :term), do: "term()"

  # --- Law-driven suggestions ------------------------------------------------
  #
  # Each law renders a real property using the function's actual call site.
  # A law that does not make sense for the arity (e.g. associativity on a
  # 1-arity function) contributes nothing.

  defp generate_for_law(:involution, ctx) do
    lib = ctx.library

    [
      property("involution: f(f(x)) == x", lib, gen_binding(lib, "input", gen(lib, :term)), """
      #{assert_stmt(lib, "#{ctx.call} |> then(&#{ctx.module}.#{ctx.func}(&1)) == input")}
      """)
    ]
  end

  # Idempotence has a clean meaning for a unary function (`f(f(x)) == f(x)`).
  # For a binary operation the meaningful form is `f(a, a) == a` — exactly what
  # `Map.merge(m, m) == m` expresses.
  defp generate_for_law(:idempotent, %{arity: 1} = ctx) do
    lib = ctx.library

    [
      property(
        "idempotence: f(f(x)) == f(x)",
        lib,
        gen_binding(lib, "input", gen(lib, :term)),
        """
        once = #{ctx.call}
        twice = #{ctx.module}.#{ctx.func}(once)
        #{assert_stmt(lib, "twice == once")}
        """
      )
    ]
  end

  defp generate_for_law(:idempotent, %{arity: 2} = ctx) do
    lib = ctx.library
    m = ctx.module
    f = ctx.func

    [
      property(
        "idempotence: f(a, a) == a",
        lib,
        gen_binding(lib, "a", gen(lib, :term)),
        """
        #{assert_stmt(lib, "#{m}.#{f}(a, a) == a")}
        """
      )
    ]
  end

  defp generate_for_law(:idempotent, ctx) do
    # Higher arities: feed the result back in as the first argument.
    lib = ctx.library
    bindings = arity_bindings(ctx)
    [_ | rest] = arg_names(ctx.arity)

    [
      property(
        "idempotence: applying twice equals applying once",
        lib,
        bindings,
        """
        once = #{ctx.call}
        twice = #{ctx.module}.#{ctx.func}(#{Enum.join(["once" | rest], ", ")})
        #{assert_stmt(lib, "twice == once")}
        """
      )
    ]
  end

  defp generate_for_law(:associative, %{arity: 2} = ctx) do
    lib = ctx.library
    m = ctx.module
    f = ctx.func

    bindings =
      gen_bindings(lib, [{"a", gen(lib, :term)}, {"b", gen(lib, :term)}, {"c", gen(lib, :term)}])

    [
      property("associativity: f(f(a, b), c) == f(a, f(b, c))", lib, bindings, """
      #{assert_stmt(lib, "#{m}.#{f}(#{m}.#{f}(a, b), c) == #{m}.#{f}(a, #{m}.#{f}(b, c))")}
      """)
    ]
  end

  defp generate_for_law(:commutative, %{arity: 2} = ctx) do
    lib = ctx.library
    m = ctx.module
    f = ctx.func

    bindings = gen_bindings(lib, [{"a", gen(lib, :term)}, {"b", gen(lib, :term)}])

    [
      property("commutativity: f(a, b) == f(b, a)", lib, bindings, """
      # NOTE: Delete this property if the operation is not commutative.
      #{assert_stmt(lib, "#{m}.#{f}(a, b) == #{m}.#{f}(b, a)")}
      """)
    ]
  end

  defp generate_for_law(:identity, %{arity: 2} = ctx) do
    lib = ctx.library
    m = ctx.module
    f = ctx.func
    identity = identity_for(ctx)

    [
      property(
        "identity element: f(a, identity) == a",
        lib,
        gen_binding(lib, "a", gen(lib, :term)),
        """
        identity = #{identity}
        #{assert_stmt(lib, "#{m}.#{f}(a, identity) == a")}
        """
      )
    ]
  end

  defp generate_for_law(:permutation, ctx) do
    lib = ctx.library

    [
      property(
        "output is a permutation of the input",
        lib,
        gen_binding(lib, "list", gen(lib, :list)),
        """
        result = #{call_with_first(ctx, "list")}
        # TODO: Replace with the invariant that holds for your function.
        #{assert_stmt(lib, "Enum.sort(result) == Enum.sort(list)")}
        """
      )
    ]
  end

  defp generate_for_law(:length_preserving, ctx) do
    lib = ctx.library

    [
      property("length is preserved", lib, gen_binding(lib, "list", gen(lib, :list)), """
      result = #{call_with_first(ctx, "list")}
      #{assert_stmt(lib, "length(result) == length(list)")}
      """)
    ]
  end

  defp generate_for_law(:monotonic, ctx) do
    lib = ctx.library

    [
      property(
        "monotonicity: a <= b implies f(a) <= f(b)",
        lib,
        gen_binding(lib, "n", gen(lib, :number)),
        """
        # TODO: Replace `n` with a generator appropriate for your domain.
        a = n
        b = n + 1
        #{assert_stmt(lib, "#{call_with_first(ctx, "a")} <= #{call_with_first(ctx, "b")}")}
        """
      )
    ]
  end

  defp generate_for_law(:bounded, ctx) do
    lib = ctx.library

    [
      property("result stays within bounds", lib, gen_binding(lib, "n", gen(lib, :number)), """
      result = #{call_with_first(ctx, "n")}
      # TODO: Replace with the real bound for your function.
      #{assert_stmt(lib, "is_number(result)")}
      """)
    ]
  end

  defp generate_for_law(:total, ctx) do
    lib = ctx.library
    bindings = arity_bindings(ctx)

    [
      property("never raises for generated input", lib, bindings, """
      # A crash here is a real bug: the function should be total over its domain.
      _ = #{ctx.call}
      """)
    ]
  end

  defp generate_for_law(:round_trip, ctx) do
    generate_for_pattern(:encoder_decoder, ctx)
  end

  defp generate_for_law(:deterministic, ctx) do
    lib = ctx.library
    bindings = arity_bindings(ctx)

    [
      property("deterministic output", lib, bindings, """
      #{assert_stmt(lib, "#{ctx.call} == #{ctx.call}")}
      """)
    ]
  end

  defp generate_for_law(_law, _ctx), do: []

  # Concrete identity when the law table knows one for a call in the body,
  # otherwise a TODO placeholder.
  defp identity_for(ctx) do
    case Map.get(ctx, :identity) do
      nil -> "nil # TODO: replace with the identity value"
      value -> value
    end
  end

  # Generate term() bindings for the function's actual arity
  defp arity_bindings(ctx) do
    bindings =
      ctx
      |> arg_names_for()
      |> Enum.map(fn name -> {name, gen(ctx.library, :term)} end)

    gen_bindings(ctx.library, bindings)
  end

  defp arg_names_for(%{arity: arity}), do: arg_names(arity)

  # --- Pattern-specific suggestion generators ---

  defp generate_for_pattern(:collection_operation, ctx) do
    lib = ctx.library
    list_binding = gen_binding(lib, "list", gen(lib, :list))

    [
      property("idempotency or invariant on collection", lib, list_binding, """
      result = #{call_with_first(ctx, "list")}
      # TODO: Replace with the invariant that holds for your function.
      # Examples: length is preserved, elements are preserved, order is maintained.
      #{assert_stmt(lib, "is_list(result)")}
      """)
    ]
  end

  defp generate_for_pattern(:transformation, ctx) do
    lib = ctx.library
    bindings = arity_bindings(ctx)

    [
      property("maintains structural invariants", lib, bindings, """
      result = #{ctx.call}
      # TODO: Replace with checks specific to your function's output structure.
      #{assert_stmt(lib, "result != nil")}
      """),
      property("deterministic output", lib, bindings, """
      result1 = #{ctx.call}
      result2 = #{ctx.call}
      #{assert_stmt(lib, "result1 == result2")}
      """)
    ]
  end

  defp generate_for_pattern(:validation, ctx) do
    lib = ctx.library
    bindings = arity_bindings(ctx)

    [
      property("returns boolean", lib, bindings, """
      result = #{ctx.call}
      #{assert_stmt(lib, "is_boolean(result)")}
      """),
      property("deterministic validation", lib, bindings, """
      #{assert_stmt(lib, "#{ctx.call} == #{ctx.call}")}
      """)
    ]
  end

  defp generate_for_pattern(:algebraic, ctx) do
    lib = ctx.library

    if ctx.arity == 2 do
      bindings_3 =
        gen_bindings(lib, [{"a", gen(lib, :term)}, {"b", gen(lib, :term)}, {"c", gen(lib, :term)}])

      bindings_2 =
        gen_bindings(lib, [{"a", gen(lib, :term)}, {"b", gen(lib, :term)}])

      m = ctx.module
      f = ctx.func

      [
        property("associativity", lib, bindings_3, """
        #{assert_stmt(lib, "#{m}.#{f}(#{m}.#{f}(a, b), c) == #{m}.#{f}(a, #{m}.#{f}(b, c))")}
        """),
        property("commutativity", lib, bindings_2, """
        # NOTE: Remove this test if the operation is not commutative.
        #{assert_stmt(lib, "#{m}.#{f}(a, b) == #{m}.#{f}(b, a)")}
        """),
        property("identity element", lib, gen_binding(lib, "a", gen(lib, :term)), """
        # TODO: Replace with the actual identity value for this operation.
        identity = nil
        #{assert_stmt(lib, "#{m}.#{f}(a, identity) == a")}
        """)
      ]
    else
      # Non-binary algebraic operations: just suggest determinism
      bindings = arity_bindings(ctx)

      [
        property("deterministic result", lib, bindings, """
        #{assert_stmt(lib, "#{ctx.call} == #{ctx.call}")}
        """)
      ]
    end
  end

  defp generate_for_pattern(:encoder_decoder, ctx) do
    lib = ctx.library
    m = ctx.module
    f = to_string(ctx.func)

    # Determine the inverse function name from the actual function name
    inverse = inverse_name(f)

    [
      property("#{f}/#{inverse} round-trip", lib, gen_binding(lib, "data", gen(lib, :term)), """
      # TODO: Replace term() with a generator that produces valid input for #{f}.
      encoded = #{m}.#{f}(data)
      # TODO: Adjust the expected return shape if #{inverse} does not return {:ok, value}.
      #{assert_stmt(lib, "#{m}.#{inverse}(encoded) == {:ok, data}")}
      """),
      property(
        "#{inverse} handles invalid input gracefully",
        lib,
        gen_binding(lib, "invalid", gen(lib, :binary)),
        """
        case #{m}.#{inverse}(invalid) do
          {:ok, _} -> true
          {:error, _} -> true
        end
        """
      )
    ]
  end

  defp generate_for_pattern(:parser, ctx) do
    lib = ctx.library
    bindings = gen_binding(lib, "input", gen(lib, :string))

    [
      property("parse returns expected structure", lib, bindings, """
      case #{ctx.module}.#{ctx.func}(input) do
        {:ok, result} ->
          # TODO: Add structural assertions for parsed output.
          #{assert_stmt(lib, "result != nil")}
        {:error, _} -> true
      end
      """),
      property("deterministic parsing", lib, bindings, """
      #{assert_stmt(lib, "#{ctx.module}.#{ctx.func}(input) == #{ctx.module}.#{ctx.func}(input)")}
      """)
    ]
  end

  defp generate_for_pattern(:numeric, ctx) do
    lib = ctx.library
    bindings = gen_binding(lib, "n", gen(lib, :number))

    call_with_n = call_with_first(ctx, "n")

    [
      property("returns numeric result", lib, bindings, """
      result = #{call_with_n}
      #{assert_stmt(lib, "is_number(result)")}
      """),
      property(
        "handles zero and negative inputs",
        lib,
        gen_binding(lib, "n", gen(lib, :number)),
        """
        # Verify the function doesn't crash on edge-case numeric inputs.
        _ = #{call_with_n}
        """
      )
    ]
  end

  defp generate_for_pattern(_type, _ctx), do: []

  # --- Helpers ---

  defp property(name, library, bindings, body) do
    snippet = """
    property "#{name}" do
      #{prop_header(library, bindings)}
    #{body}
      end
    end
    """

    format_code(snippet)
  end

  defp format_code(snippet) do
    snippet
    |> Code.format_string!()
    |> IO.iodata_to_binary()
  rescue
    _ -> String.trim(snippet)
  end

  @inverse_pairs %{
    "encode" => "decode",
    "decode" => "encode",
    "serialize" => "deserialize",
    "deserialize" => "serialize",
    "pack" => "unpack",
    "unpack" => "pack",
    "marshal" => "unmarshal",
    "unmarshal" => "marshal",
    "compress" => "decompress",
    "decompress" => "compress",
    "encrypt" => "decrypt",
    "decrypt" => "encrypt"
  }

  defp inverse_name(func_name) do
    name = to_string(func_name)
    segments = String.split(name, "_")

    # Try to find the inverse by checking each segment
    case Enum.find(segments, &Map.has_key?(@inverse_pairs, &1)) do
      nil ->
        # Fallback: just suggest a decode-like name
        "decode"

      segment ->
        inverse_segment = @inverse_pairs[segment]
        String.replace(name, segment, inverse_segment, global: false)
    end
  end
end
