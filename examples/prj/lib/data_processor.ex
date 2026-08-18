defmodule ExampleProject.DataProcessor do
  @moduledoc """
  Exemplary module with pure functions fitting for property testing as well as impure functions.
  """

  @doc """
  Encodes a map payload into a binary representation.
  """
  def encode_payload(data) when is_map(data) do
    data
    |> :erlang.term_to_binary()
    |> Base.encode64()
  end

  @doc """
  Decodes a binary representation back into a map payload.
  """
  def decode_payload(encoded) when is_binary(encoded) do
    case Base.decode64(encoded) do
      {:ok, binary} -> {:ok, :erlang.binary_to_term(binary)}
      :error -> {:error, :invalid_format}
    end
  end

  @doc """
  Transforms a list of numeric metrics by normalizing and filtering positive values.
  """
  def transform_metrics(metrics) when is_list(metrics) do
    metrics
    |> Enum.filter(fn x -> is_number(x) and x > 0 end)
    |> Enum.map(fn x -> x * 1.05 + 2.0 end)
  end

  @doc """
  Validates whether a string is a valid email format.
  """
  def valid_email?(email) when is_binary(email) do
    Regex.match?(~r/^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$/, email)
  end

  @doc """
  Merges two configuration maps algebraically.
  """
  def merge_configs(base, override) when is_map(base) and is_map(override) do
    Map.merge(base, override, fn _key, v1, v2 ->
      if is_map(v1) and is_map(v2), do: merge_configs(v1, v2), else: v2
    end)
  end

  @doc """
  Parses a CSV line into a list of field tokens.
  """
  def parse_csv_line(line) when is_binary(line) do
    line
    |> String.trim()
    |> String.split(",")
    |> Enum.map(&String.trim/1)
  end

  @doc """
  Calculates Euclidean distance between two 2D points.
  """
  def calculate_distance(x1, y1, x2, y2) do
    dx = x2 - x1
    dy = y2 - y1
    :math.sqrt(dx * dx + dy * dy)
  end

  @doc """
  Impure function that performs disk I/O and logging. (Should score 0 in propwise).
  """
  def save_metrics(metrics, file_path) do
    IO.puts("Saving metrics to #{file_path}...")
    File.write!(file_path, inspect(metrics))
    :ok
  end
end
