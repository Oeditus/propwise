defmodule PropWise.Parser do
  @moduledoc """
  Parses Elixir source files and extracts function definitions with their ASTs.
  """

  alias PropWise.{Config, FunctionInfo}

  @doc """
  Parses all `.ex` files in the given directory recursively.
  Returns a list of `PropWise.FunctionInfo` structs.

  Accepts an optional `analyze_paths` list to avoid re-loading config.
  """
  @spec parse_project(String.t(), keyword()) :: [FunctionInfo.t()]
  def parse_project(path, opts \\ []) do
    path
    |> find_elixir_files(opts)
    |> Enum.flat_map(&parse_file/1)
  end

  @doc """
  Parses a single Elixir file and extracts all function definitions.
  """
  @spec parse_file(String.t()) :: [FunctionInfo.t()]
  def parse_file(file_path) do
    with {:ok, content} <- File.read(file_path),
         {:ok, ast} <- Code.string_to_quoted(content) do
      extract_functions(ast, file_path)
    else
      _ -> []
    end
  end

  defp find_elixir_files(path, opts) do
    analyze_paths = Keyword.get(opts, :analyze_paths) || Config.analyze_paths(path)

    effective_paths = maybe_expand_umbrella(path, analyze_paths)

    effective_paths
    |> Enum.flat_map(fn relative_path ->
      full_path = Path.join(path, relative_path)

      if File.dir?(full_path) do
        Path.join(full_path, "**/*.ex")
        |> Path.wildcard()
      else
        []
      end
    end)
  end

  # When analyze_paths is the default ["lib"] and no lib/ exists at the root,
  # but an apps/ directory does, expand to apps/*/lib automatically.
  defp maybe_expand_umbrella(path, ["lib"] = _default_paths) do
    lib_path = Path.join(path, "lib")
    apps_path = Path.join(path, "apps")

    if not File.dir?(lib_path) and File.dir?(apps_path) do
      apps_path
      |> File.ls!()
      |> Enum.map(&Path.join("apps", Path.join(&1, "lib")))
      |> Enum.filter(&File.dir?(Path.join(path, &1)))
    else
      ["lib"]
    end
  end

  defp maybe_expand_umbrella(_path, custom_paths), do: custom_paths

  defp extract_functions(ast, file_path) do
    {_ast, functions} =
      Macro.prewalk(ast, [], fn
        {:defmodule, _meta, [module_alias, [do: block]]} = node, acc ->
          module_name = extract_module_name(module_alias)
          module_functions = extract_module_functions(block, module_name, file_path)
          {node, acc ++ module_functions}

        node, acc ->
          {node, acc}
      end)

    functions
  end

  defp extract_module_functions(block, module_name, file_path) do
    {_ast, functions} =
      Macro.prewalk(block, [], fn
        {:def, meta, [{name, _meta2, args}, body]} = node, acc when is_list(args) ->
          function_info = %FunctionInfo{
            module: module_name,
            name: name,
            arity: length(args),
            args: args,
            body: body,
            file: file_path,
            line: meta[:line],
            type: :public
          }

          {node, [function_info | acc]}

        {:defp, meta, [{name, _meta2, args}, body]} = node, acc when is_list(args) ->
          function_info = %FunctionInfo{
            module: module_name,
            name: name,
            arity: length(args),
            args: args,
            body: body,
            file: file_path,
            line: meta[:line],
            type: :private
          }

          {node, [function_info | acc]}

        node, acc ->
          {node, acc}
      end)

    Enum.reverse(functions)
  end

  defp extract_module_name({:__aliases__, _meta, parts}) do
    Enum.map_join(parts, ".", &to_string/1)
  end

  defp extract_module_name(atom) when is_atom(atom), do: to_string(atom)
  defp extract_module_name(_), do: "Unknown"
end
