defmodule PropWise.Parser do
  @moduledoc """
  Parses Elixir source files and extracts function definitions with their ASTs using Metastatic.
  """

  alias PropWise.{Config, FunctionInfo}

  @doc """
  Parses Elixir files in the given path or file list.
  Returns a list of `PropWise.FunctionInfo` structs.

  Accepts optional `analyze_paths` or `files` options.
  """
  @spec parse_project(String.t(), keyword()) :: [FunctionInfo.t()]
  def parse_project(path, opts \\ []) do
    path
    |> resolve_files(opts)
    |> Enum.flat_map(&parse_file/1)
  end

  @doc """
  Parses a single Elixir file and extracts all function definitions.
  """
  @spec parse_file(String.t()) :: [FunctionInfo.t()]
  def parse_file(file_path) do
    with {:ok, content} <- File.read(file_path),
         {:ok, meta_ast} <- Metastatic.quote(content, :elixir) do
      extract_functions(meta_ast, file_path)
    else
      _ -> []
    end
  end

  defp resolve_files(path, opts) do
    cond do
      files_opt = Keyword.get(opts, :files) ->
        parse_files_list(path, files_opt)

      File.regular?(path) ->
        [path]

      File.dir?(path) ->
        find_elixir_files(path, opts)

      true ->
        []
    end
  end

  defp parse_files_list(base_path, files) when is_list(files) do
    Enum.flat_map(files, &parse_files_list(base_path, &1))
  end

  defp parse_files_list(base_path, files_str) when is_binary(files_str) do
    files_str
    |> String.split(",")
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.flat_map(fn file ->
      joined = Path.join(base_path, file)

      target =
        cond do
          File.exists?(joined) -> joined
          File.exists?(file) -> file
          true -> joined
        end

      cond do
        File.regular?(target) -> [target]
        File.dir?(target) -> Path.wildcard(Path.join(target, "**/*.ex"))
        true -> []
      end
    end)
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

  defp extract_functions(meta_ast, file_path) do
    {_ast, {_, functions}} =
      Metastatic.traverse(
        meta_ast,
        {nil, []},
        fn node, {current_mod, acc} -> process_node(node, current_mod, acc, file_path) end,
        fn node, acc -> {node, acc} end
      )

    Enum.reverse(functions)
  end

  defp process_node({:container, meta, _children} = node, _current_mod, acc, _file_path) do
    mod_name = meta[:name] || meta[:module] || "Unknown"
    {node, {mod_name, acc}}
  end

  defp process_node({:function_def, meta, children} = node, current_mod, acc, file_path) do
    info = build_function_info(meta, children, current_mod, file_path)
    {node, {current_mod, [info | acc]}}
  end

  defp process_node(node, current_mod, acc, _file_path) do
    {node, {current_mod, acc}}
  end

  defp build_function_info(meta, children, current_mod, file_path) do
    name_atom = parse_name(meta[:name])
    arity = meta[:arity] || count_params(meta[:params])
    visibility = parse_visibility(meta)
    body = wrap_body(children)

    %FunctionInfo{
      module: current_mod || "Unknown",
      name: name_atom,
      arity: arity,
      args: meta[:params] || [],
      body: body,
      file: file_path,
      line: meta[:line] || 1,
      type: visibility
    }
  end

  defp parse_name(s) when is_binary(s), do: String.to_atom(s)
  defp parse_name(a) when is_atom(a), do: a
  defp parse_name(_), do: :unknown

  defp parse_visibility(meta) do
    if meta[:visibility] == :private or meta[:type] == :private do
      :private
    else
      :public
    end
  end

  defp wrap_body([single]), do: single
  defp wrap_body(multiple), do: {:block, [], multiple}

  defp count_params(params) when is_list(params), do: length(params)
  defp count_params(_), do: 0
end
