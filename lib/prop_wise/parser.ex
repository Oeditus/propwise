defmodule PropWise.Parser do
  @moduledoc """
  Parses Elixir source files and extracts function definitions with their ASTs.
  """

  @doc """
  Parses all `.ex` files in the given directory recursively.
  Returns a list of function metadata.
  """
  def parse_project(path) do
    path
    |> find_elixir_files()
    |> Enum.flat_map(&parse_file/1)
  end

  @doc """
  Parses a single Elixir file and extracts all function definitions.
  """
  def parse_file(file_path) do
    with {:ok, content} <- File.read(file_path),
         {:ok, ast} <- Code.string_to_quoted(content) do
      extract_functions(ast, file_path)
    else
      _ -> []
    end
  end

  defp find_elixir_files(path) do
    Path.join(path, "**/*.ex")
    |> Path.wildcard()
    |> Enum.reject(&String.contains?(&1, ["/_build/", "/deps/", "/.elixir_ls/"]))
  end

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
          function_info = %{
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
          function_info = %{
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
    parts |> Enum.map(&to_string/1) |> Enum.join(".")
  end

  defp extract_module_name(atom) when is_atom(atom), do: to_string(atom)
  defp extract_module_name(_), do: "Unknown"
end
