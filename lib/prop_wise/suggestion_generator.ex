defmodule PropWise.SuggestionGenerator do
  @moduledoc """
  Generates property-based testing suggestions for different libraries.

  Uses a template-based approach where library-specific syntax (stream_data vs PropEr)
  is parameterized, and function name/arity are used to generate accurate call sites.
  """

  @doc """
  Generates testing suggestions based on detected patterns and library.
  """
  @spec generate([PropWise.Candidate.pattern()], PropWise.FunctionInfo.t() | map(), atom()) ::
          [String.t()]
  def generate(patterns, function_info, library) do
    ctx = build_context(function_info, library)

    patterns
    |> Enum.flat_map(fn {type, _reason} ->
      generate_for_pattern(type, ctx)
    end)
    |> Enum.uniq()
  end

  defp build_context(function_info, library) do
    module_name = function_info.module |> String.split(".") |> List.last()
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
      result = #{ctx.call |> replace_first_arg("list")}
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

    call_with_n = ctx.call |> replace_first_arg("n")

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
    body = body |> String.trim_trailing() |> indent(6)

    """
    property "#{name}" do
      #{prop_header(library, bindings)}
    #{body}
      end
    end
    """
  end

  defp indent(text, n) do
    pad = String.duplicate(" ", n)

    text
    |> String.split("\n")
    |> Enum.map_join("\n", fn
      "" -> ""
      line -> pad <> line
    end)
  end

  defp replace_first_arg(call, new_arg) do
    # Replace the first argument in a call string like "Module.func(input)" -> "Module.func(n)"
    Regex.replace(~r/\(([^,\)]+)/, call, "(#{new_arg}", global: false)
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
    "compress" => "compress",
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
