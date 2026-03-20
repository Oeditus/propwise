defmodule PropWise.ReporterTest do
  use ExUnit.Case, async: true

  alias PropWise.Reporter

  defp sample_result(opts \\ []) do
    candidates = Keyword.get(opts, :candidates, [])
    inverse_pairs = Keyword.get(opts, :inverse_pairs, [])

    %{
      candidates: candidates,
      inverse_pairs: inverse_pairs,
      total_functions: Keyword.get(opts, :total, 10),
      candidates_count: length(candidates),
      dropped_count: Keyword.get(opts, :dropped, 0)
    }
  end

  defp sample_candidate(opts \\ []) do
    %{
      module: Keyword.get(opts, :module, "MyModule"),
      name: Keyword.get(opts, :name, :my_func),
      arity: Keyword.get(opts, :arity, 1),
      file: Keyword.get(opts, :file, "/project/lib/my_module.ex"),
      line: Keyword.get(opts, :line, 42),
      type: Keyword.get(opts, :type, :public),
      purity: {:pure, []},
      patterns: Keyword.get(opts, :patterns, [{:collection_operation, "Uses Enum"}]),
      score: Keyword.get(opts, :score, 5),
      suggestions: Keyword.get(opts, :suggestions, ["test property X"])
    }
  end

  describe "format_report/2 - text format" do
    test "includes summary section" do
      report = Reporter.format_report(sample_result())

      assert report =~ "PropWise Analysis Report"
      assert report =~ "Total functions analyzed: 10"
      assert report =~ "Property test candidates: 0"
    end

    test "includes candidate details" do
      result = sample_result(candidates: [sample_candidate()])
      report = Reporter.format_report(result)

      assert report =~ "MyModule.my_func/1"
      assert report =~ "Score: 5"
    end

    test "shows coverage percentage" do
      result = sample_result(candidates: [sample_candidate()], total: 10)
      report = Reporter.format_report(result)

      assert report =~ "Coverage: 10.0%"
    end

    test "handles empty candidates" do
      report = Reporter.format_report(sample_result())

      assert report =~ "No strong candidates found"
    end

    test "shows inverse pairs when present" do
      pair = %{
        type: :inverse_pair,
        forward: {"Codec", :encode, 1},
        inverse: {"Codec", :decode, 1},
        suggestion: "Test round-trip"
      }

      result = sample_result(inverse_pairs: [pair])
      report = Reporter.format_report(result)

      assert report =~ "Inverse Function Pairs"
      assert report =~ "encode/1"
      assert report =~ "decode/1"
    end

    test "shows dropped count" do
      result = sample_result(dropped: 5)
      report = Reporter.format_report(result)

      assert report =~ "Candidates dropped (below threshold): 5"
    end
  end

  describe "format_report/2 - JSON format" do
    test "produces valid JSON" do
      result = sample_result(candidates: [sample_candidate()])
      json = Reporter.format_report(result, format: :json)

      assert {:ok, decoded} = Jason.decode(json)
      assert is_map(decoded)
      assert Map.has_key?(decoded, "candidates")
      assert Map.has_key?(decoded, "total_functions")
    end

    test "serializes candidate data correctly" do
      result = sample_result(candidates: [sample_candidate(name: :encode_data, score: 7)])
      json = Reporter.format_report(result, format: :json)
      {:ok, decoded} = Jason.decode(json)

      [candidate] = decoded["candidates"]
      assert candidate["name"] == "encode_data"
      assert candidate["score"] == 7
      assert candidate["module"] == "MyModule"
    end

    test "serializes inverse pairs" do
      pair = %{
        type: :inverse_pair,
        forward: {"Codec", :encode, 1},
        inverse: {"Codec", :decode, 1},
        suggestion: "Test round-trip"
      }

      result = sample_result(inverse_pairs: [pair])
      json = Reporter.format_report(result, format: :json)
      {:ok, decoded} = Jason.decode(json)

      [pair_data] = decoded["inverse_pairs"]
      assert pair_data["forward"]["name"] == "encode"
      assert pair_data["inverse"]["name"] == "decode"
    end

    test "handles empty result" do
      json = Reporter.format_report(sample_result(), format: :json)
      {:ok, decoded} = Jason.decode(json)

      assert decoded["candidates"] == []
      assert decoded["candidates_count"] == 0
    end
  end
end
