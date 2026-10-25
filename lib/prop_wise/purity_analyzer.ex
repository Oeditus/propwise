defmodule PropWise.PurityAnalyzer do
  @moduledoc """
  Analyzes function ASTs (MetaAST from Metastatic) to classify them as
  `:pure`, `:unknown` or `:impure`.

  ## Why three states?

  A binary pure/impure split forces every function that calls *any* other
  function to be guessed at. `MyApp.Helpers.normalize/1` might be a pure list
  transform or might hit the database — a static analyzer cannot know without
  following the call. Treating both as "pure" produces false positives;
  treating both as "impure" produces false negatives.

  PropWise therefore distinguishes:

    * `:pure` — every call in the body is to a known-pure function. No
      side-effect call was found and no unresolved call remains.
    * `:unknown` — no side effect was found, but the body calls something we
      cannot resolve (another module's function, an unqualified local call).
    * `:impure` — a known side effect was found.

  `:unknown` candidates are still reported, but at a reduced score weight
  (see `PropWise.Analyzer`), so genuinely clean functions rank first.

  ## Configuration

  Detection can be customized with options:

      analyze(function_info,
        side_effect_calls: [...],
        side_effect_functions: [...],
        pure_modules: [MyApp.Math]
      )

  ### `:side_effect_calls`

  List of `{module, function, arity}` tuples that indicate side effects.
  Supports wildcards:

    * `{Module, :*, :*}` — all functions in module
    * `{Module, :function, :*}` — all arities of function

  ### `:side_effect_functions`

  List of `{function, arity}` tuples for bare calls that indicate side effects.

  ### `:pure_modules`

  List of modules (or module prefixes) whose functions are known to be pure.
  A call into one of these modules does not make the caller `:unknown`.

  Built-in pure modules (`Enum`, `Map`, `List`, `String`, `Integer`, `Float`,
  `Kernel`, `Tuple`, `Keyword`, `MapSet`, `Range`, `Access`, `Enum`, `Stream`,
  `Base`, `Jason`, `:erlang`, `:lists`, `:maps`, `:binary`, `:math`, `:string`,
  `:unicode`) are always assumed pure.
  """

  alias Metastatic.Adapters.Elixir.ToMeta
  alias Metastatic.Semantic.Enricher

  @typedoc "Purity classification of a function."
  @type purity :: :pure | :unknown | :impure

  @typedoc "A detected side effect."
  @type side_effect ::
          {:semantic_op, atom(), atom()}
          | {:module_call, module(), atom(), non_neg_integer()}
          | {:function_call, atom(), non_neg_integer()}
          | {:receive_block}

  @typedoc "Result of a purity analysis."
  @type result :: %{
          purity: purity(),
          side_effects: [side_effect()],
          unresolved_calls: [String.t()]
        }

  # Default side effect module calls
  @default_side_effect_calls [
    # I/O operations
    {IO, :*, :*},
    {File, :*, :*},
    {Logger, :*, :*},
    # Process operations
    {GenServer, :*, :*},
    {Agent, :*, :*},
    {Task, :*, :*},
    {Process, :send, :*},
    {Process, :send_after, :*},
    {Process, :exit, :*},
    {Process, :flag, :*},
    {Process, :put, :*},
    {Process, :register, :*},
    {Process, :unregister, :*},
    # Database operations
    {Ecto.Repo, :*, :*},
    {Ecto.Query, :*, :*},
    # HTTP operations
    {Req, :*, :*},
    # System operations
    {System, :*, :*},
    {:ets, :*, :*},
    {:dets, :*, :*},
    {:mnesia, :*, :*},
    # Supervision
    {Registry, :*, :*},
    {DynamicSupervisor, :*, :*},
    {Supervisor, :*, :*},
    # Telemetry
    {:telemetry, :span, 3}
  ]

  # Default side effect bare functions
  @default_side_effect_functions [
    {:send, 2},
    {:spawn, 1},
    {:spawn, 3},
    {:spawn_link, 1},
    {:spawn_link, 3}
  ]

  # Modules whose functions are known to be pure. A call into one of these does
  # not downgrade a function to `:unknown`.
  @default_pure_modules [
    Access,
    Base,
    Bitwise,
    Enum,
    Float,
    Function,
    Integer,
    Jason,
    Kernel,
    Keyword,
    List,
    Map,
    MapSet,
    Range,
    Regex,
    Stream,
    String,
    Tuple,
    URI,
    Version,
    :binary,
    :calendar,
    :erlang,
    :lists,
    :math,
    :maps,
    :string,
    :unicode
  ]

  # `Kernel` functions that are *not* pure even though `Kernel` is a pure module.
  @kernel_impure [:send, :spawn, :spawn_link, :spawn_monitor, :exit, :raise, :throw]

  @doc """
  Analyzes a function and returns its purity classification.

  Returns a map with `:purity` (`:pure` | `:unknown` | `:impure`),
  `:side_effects` (list) and `:unresolved_calls` (list of call names that
  could not be resolved either way).

  ## Options

    * `:side_effect_calls` — list of `{module, function, arity}` tuples
    * `:side_effect_functions` — list of `{function, arity}` tuples
    * `:pure_modules` — extra modules whose functions are considered pure

  ## Examples

      iex> analyze(%{body: quote(do: Enum.map(x, & &1))}).purity
      :pure

      iex> analyze(%{body: quote(do: IO.puts("hi"))}).purity
      :impure

  """
  @spec analyze(PropWise.FunctionInfo.t() | map(), keyword()) :: result()
  def analyze(function_info, opts \\ []) do
    side_effect_calls = Keyword.get(opts, :side_effect_calls, @default_side_effect_calls)

    side_effect_functions =
      Keyword.get(opts, :side_effect_functions, @default_side_effect_functions)

    pure_modules = @default_pure_modules ++ Keyword.get(opts, :pure_modules, [])

    meta_ast = ensure_meta_ast(function_info.body)
    classify(meta_ast, side_effect_calls, side_effect_functions, pure_modules)
  end

  @doc """
  Returns the purity classification only (`:pure` | `:unknown` | `:impure`).

  Accepts the same options as `analyze/2`.
  """
  @spec classify(PropWise.FunctionInfo.t() | map(), keyword()) :: purity()
  def classify(function_info, opts \\ []) do
    function_info |> analyze(opts) |> Map.fetch!(:purity)
  end

  @doc """
  Returns true if the function is classified `:pure`.

  Note that `:unknown` functions return `false` here — use `classify/2` if you
  need to distinguish "definitely impure" from "cannot tell".
  """
  @spec pure?(PropWise.FunctionInfo.t() | map(), keyword()) :: boolean()
  def pure?(function_info, opts \\ []) do
    classify(function_info, opts) == :pure
  end

  # ----- Helpers -----

  @doc false
  def ensure_meta_ast(ast) do
    cond do
      meta_ast?(ast) ->
        ast

      is_list(ast) ->
        case Enum.map(ast, &ensure_meta_ast/1) do
          [single] -> single
          items -> {:block, [], items}
        end

      true ->
        case ToMeta.transform(ast) do
          {:ok, meta_ast, _metadata} ->
            Enricher.enrich_tree(meta_ast, :elixir)

          _ ->
            ast
        end
    end
  end

  @meta_types [
    :literal,
    :variable,
    :binary_op,
    :unary_op,
    :function_call,
    :conditional,
    :pattern_match,
    :block,
    :list,
    :map,
    :tuple,
    :container,
    :function_def,
    :comprehension,
    :generator,
    :lambda,
    :pair,
    :match_arm,
    :import,
    :type_annotation,
    :return,
    :try,
    :catch,
    :throw,
    :raise,
    :collection_op
  ]

  defp meta_ast?({type, meta, _}) when type in @meta_types and is_list(meta), do: true
  defp meta_ast?(_), do: false

  defp classify(meta_ast, side_calls, side_funcs, pure_modules) do
    {_ast, acc} =
      Metastatic.traverse(
        meta_ast,
        %{side_effects: [], unresolved: []},
        fn node, acc -> {node, inspect_call(node, acc, side_calls, side_funcs, pure_modules)} end,
        fn node, acc -> {node, acc} end
      )

    side_effects = Enum.reverse(acc.side_effects)
    unresolved = acc.unresolved |> Enum.reverse() |> Enum.uniq()

    purity =
      cond do
        side_effects != [] -> :impure
        unresolved != [] -> :unknown
        true -> :pure
      end

    %{purity: purity, side_effects: side_effects, unresolved_calls: unresolved}
  end

  defp inspect_call(node, acc, side_calls, side_funcs, pure_modules) do
    case detect_side_effect(node, side_calls, side_funcs, pure_modules) do
      {:effect, effect} ->
        %{acc | side_effects: [effect | acc.side_effects]}

      {:unresolved, name} ->
        %{acc | unresolved: [name | acc.unresolved]}

      :resolved ->
        acc

      :ignore ->
        # A piped call whose target could not be resolved still counts as
        # unresolved: we must not treat it as pure.
        if piped_dotted_call?(node) do
          {:function_call, meta, _} = node
          %{acc | unresolved: [to_string(meta[:name] || "?") | acc.unresolved]}
        else
          acc
        end
    end
  end

  # Classifies a single node as an effect, an unresolved call, a resolved pure
  # call, or "not a call at all".
  defp detect_side_effect({:function_call, meta, args}, side_calls, side_funcs, pure_modules)
       when is_list(args) do
    call_name = to_string(meta[:name] || "")

    cond do
      semantic_effect(meta) ->
        {:effect, semantic_effect(meta)}

      call_name == "receive" ->
        {:effect, {:receive_block}}

      # Checked before name-based resolution: a piped call into a dotted module
      # carries a mangled `name` (Metastatic may leave a stale name such as
      # `"Map.fetch!"`), so trusting the name here would wrongly resolve it.
      piped_dotted_call?({:function_call, meta, args}) ->
        {:unresolved, call_name}

      String.contains?(call_name, ".") ->
        classify_qualified(call_name, args, side_calls, pure_modules)

      true ->
        classify_local(call_name, args, side_funcs)
    end
  end

  defp detect_side_effect(_node, _calls, _funcs, _pure_modules), do: :ignore

  # A semantic `op_kind` domain is the strongest possible signal.
  defp semantic_effect(meta) do
    op_kind = meta[:op_kind]
    domain = op_kind && op_kind[:domain]

    if domain in [:db, :http, :cache, :file, :auth, :queue, :external_api] do
      {:semantic_op, domain, op_kind[:operation] || :op}
    end
  end

  # `Module.function(...)` — resolve against the side-effect table, then the
  # known-pure module list, and fall back to "unresolved".
  defp classify_qualified(call_name, args, side_calls, pure_modules) do
    {mod_str, fn_str} = split_call_name(call_name)
    module = parse_module(mod_str)
    func = String.to_atom(fn_str)
    arity = length(args)

    cond do
      side_effect_call?(module, func, arity, side_calls) ->
        {:effect, {:module_call, module, func, arity}}

      pure_module?(module, func, pure_modules) ->
        :resolved

      true ->
        {:unresolved, call_name}
    end
  end

  # An unqualified call may be a local helper or an import; it can never be
  # resolved statically, so it makes the function `:unknown` rather than `:pure`.
  defp classify_local(call_name, args, side_funcs) do
    func = String.to_atom(call_name)
    arity = length(args)

    if {func, arity} in side_funcs or func in @kernel_impure do
      {:effect, {:function_call, func, arity}}
    else
      {:unresolved, call_name}
    end
  end

  # Metastatic renders a piped call into a dotted module as a call whose name is
  # the *last* segment, with the module alias and function name as trailing
  # arguments (e.g. `x |> MyApp.post_process()` becomes a call named
  # `"post_process"` with `MyApp` and `:post_process` among its args). Such a
  # call can never be resolved statically, so treat it as unresolved rather than
  # silently assuming purity.
  defp piped_dotted_call?({:function_call, meta, args}) do
    meta[:pipe] == true and
      Enum.any?(args, fn
        {:variable, vmeta, _} -> Keyword.get(vmeta, :original_meta, [])[:alias] == false
        _ -> false
      end)
  end

  defp piped_dotted_call?(_node), do: false

  # A call is "resolved pure" when its module is in the known-pure set (defaults
  # plus any user-configured `:pure_modules`) and the function is not one of the
  # few impure `Kernel` functions.
  defp pure_module?(module, func, pure_modules) do
    module in pure_modules and not (module == Kernel and func in @kernel_impure)
  end

  defp split_call_name(call_name) do
    parts = String.split(call_name, ".")
    fn_name = List.last(parts)
    mod_parts = Enum.drop(parts, -1)
    mod_str = Enum.join(mod_parts, ".")
    {mod_str, fn_name}
  end

  defp parse_module(":" <> atom_str), do: String.to_atom(atom_str)

  defp parse_module(mod_str) do
    parts = String.split(mod_str, ".")

    if Enum.all?(parts, &valid_alias?/1) do
      Module.concat(parts)
    else
      String.to_atom(mod_str)
    end
  end

  defp valid_alias?(str), do: Regex.match?(~r/^[A-Z][a-zA-Z0-9_]*$/, str)

  # Check if a module call matches any side effect pattern
  defp side_effect_call?(module, function, arity, side_effect_calls) do
    Enum.any?(side_effect_calls, fn
      # Exact match: {Module, :function, arity}
      {^module, ^function, ^arity} -> true
      # Module wildcard: {Module, :*, :*}
      {^module, :*, :*} -> true
      # Function wildcard: {Module, :function, :*}
      {^module, ^function, :*} -> true
      # No match
      _ -> false
    end)
  end
end
