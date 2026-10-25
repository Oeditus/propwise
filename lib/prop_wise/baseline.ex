defmodule PropWise.Baseline do
  @moduledoc """
  Baseline support for CI ratcheting.

  A baseline is a JSON snapshot of the candidates that already existed when you
  adopted PropWise. On subsequent runs, `--baseline FILE` reports only
  **newly qualifying** candidates — the ones your change introduced.

  This turns PropWise from "a report nobody reads" into a ratchet: the count of
  accepted candidates can only go down unless someone consciously updates the
  baseline.

  ## Identity

  A candidate is identified by `{module, name, arity}`. Its *score* is recorded
  too, so a function whose score rises above the baseline is reported as
  improved (and therefore newly actionable) rather than silently accepted.

  ## File format

      {
        "version": 1,
        "generated_at": "2026-04-01T12:00:00Z",
        "candidates": [
          {"module": "MyApp.Foo", "name": "bar", "arity": 1, "score": 6}
        ]
      }

  ## Usage

      # Snapshot the current state
      mix propwise --write-baseline .propwise/baseline.json

      # In CI: fail only on newly introduced candidates
      mix propwise --baseline .propwise/baseline.json
  """

  @version 1

  @typedoc "A single baselined entry."
  @type entry :: %{
          module: String.t(),
          name: String.t(),
          arity: non_neg_integer(),
          score: non_neg_integer()
        }

  @typedoc "A parsed baseline."
  @type t :: %{
          version: pos_integer(),
          generated_at: String.t() | nil,
          candidates: %{{String.t(), String.t(), non_neg_integer()} => non_neg_integer()}
        }

  @doc """
  Builds a baseline map from an analysis result.
  """
  @spec from_result(PropWise.Analyzer.analysis_result()) :: t()
  def from_result(%{candidates: candidates}) do
    entries =
      Map.new(candidates, fn candidate ->
        {{candidate.module, to_string(candidate.name), candidate.arity}, candidate.score}
      end)

    %{version: @version, generated_at: now_iso8601(), candidates: entries}
  end

  @doc """
  Serialises a baseline to the on-disk JSON representation.
  """
  @spec to_json(t()) :: String.t()
  def to_json(%{candidates: candidates} = baseline) do
    payload = %{
      "version" => Map.get(baseline, :version, @version),
      "generated_at" => Map.get(baseline, :generated_at) || now_iso8601(),
      "candidates" =>
        candidates
        |> Enum.map(fn {{module, name, arity}, score} ->
          %{"module" => module, "name" => name, "arity" => arity, "score" => score}
        end)
        |> Enum.sort_by(&{&1["module"], &1["name"], &1["arity"]})
    }

    Jason.encode!(payload, pretty: true)
  end

  @doc """
  Writes a baseline to `path`, creating parent directories as needed.

  Returns `:ok` or `{:error, reason}`.
  """
  @spec write(String.t(), t()) :: :ok | {:error, term()}
  def write(path, baseline) do
    with :ok <- File.mkdir_p(Path.dirname(path)) do
      File.write(path, to_json(baseline))
    end
  end

  @doc """
  Reads and parses a baseline file.

  Returns `{:ok, baseline}` or `{:error, reason}`. A malformed or
  unrecognised file is an error rather than a silent empty baseline — silently
  treating an unreadable baseline as "nothing was accepted before" would make
  every existing candidate look new and flood CI.
  """
  @spec read(String.t()) :: {:ok, t()} | {:error, term()}
  def read(path) do
    with {:ok, contents} <- File.read(path),
         {:ok, decoded} <- Jason.decode(contents) do
      parse(decoded)
    end
  end

  @doc """
  Parses an already-decoded baseline document.
  """
  @spec parse(map()) :: {:ok, t()} | {:error, term()}
  def parse(%{"candidates" => candidates} = doc) when is_list(candidates) do
    entries =
      Enum.reduce_while(candidates, %{}, fn entry, acc ->
        case entry do
          %{"module" => module, "name" => name, "arity" => arity} = e
          when is_binary(module) and is_binary(name) and is_integer(arity) ->
            score = Map.get(e, "score", 0)
            {:cont, Map.put(acc, {module, name, arity}, score)}

          other ->
            {:halt, {:error, {:invalid_entry, other}}}
        end
      end)

    case entries do
      {:error, _} = error ->
        error

      map ->
        {:ok,
         %{
           version: Map.get(doc, "version", @version),
           generated_at: Map.get(doc, "generated_at"),
           candidates: map
         }}
    end
  end

  def parse(other), do: {:error, {:invalid_baseline, other}}

  @doc """
  Partitions candidates into those already present in the baseline and those
  that are new or whose score has increased.

  Returns `%{new: [...], known: [...]}`.

  A candidate counts as `:new` when its `{module, name, arity}` is absent from
  the baseline, **or** when its score is strictly higher than the baselined
  score (the function got worse, so it deserves attention again).
  """
  @spec diff(t(), [PropWise.Candidate.t()]) :: %{
          new: [PropWise.Candidate.t()],
          known: [PropWise.Candidate.t()]
        }
  def diff(%{candidates: baselined}, candidates) do
    Enum.split_with(candidates, fn candidate ->
      key = {candidate.module, to_string(candidate.name), candidate.arity}

      case Map.fetch(baselined, key) do
        :error -> true
        {:ok, score} -> candidate.score > score
      end
    end)
    |> then(fn {new, known} -> %{new: new, known: known} end)
  end

  @doc """
  Returns a copy of `analysis_result` containing only the candidates that are
  new or whose score increased relative to `baseline`.

  `inverse_pairs` are filtered to pairs where at least one side survives.
  """
  @spec apply_to_result(t(), PropWise.Analyzer.analysis_result()) ::
          PropWise.Analyzer.analysis_result()
  def apply_to_result(baseline, result) do
    %{new: new_candidates} = diff(baseline, result.candidates)

    surviving = MapSet.new(new_candidates, &{&1.module, to_string(&1.name), &1.arity})

    inverse_pairs =
      Enum.filter(result.inverse_pairs, fn pair ->
        {m1, n1, a1} = pair.forward
        {m2, n2, a2} = pair.inverse

        MapSet.member?(surviving, {m1, to_string(n1), a1}) or
          MapSet.member?(surviving, {m2, to_string(n2), a2})
      end)

    %{
      result
      | candidates: new_candidates,
        inverse_pairs: inverse_pairs,
        candidates_count: length(new_candidates)
    }
  end

  @doc """
  Returns the number of candidates in the baseline.
  """
  @spec size(t()) :: non_neg_integer()
  def size(%{candidates: candidates}), do: map_size(candidates)

  defp now_iso8601 do
    DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601()
  end
end
