defmodule PropWise.BaselineTest do
  @moduledoc """
  Tests for baseline CI ratcheting.

  Acceptance criterion: `--baseline` loads a baseline, reports regressions
  separately from pre-existing violations, and exits non-zero only on
  regressions.
  """

  use ExUnit.Case, async: true

  alias PropWise.{Baseline, CommandLine}

  defp candidate(module, name, arity, score) do
    %{
      module: module,
      name: name,
      arity: arity,
      file: "lib/x.ex",
      line: 1,
      type: :public,
      purity: :pure,
      side_effects: [],
      unresolved_calls: [],
      patterns: [],
      laws: [],
      score: score,
      rank: 1,
      inverse_pair: false,
      suggestions: []
    }
  end

  defp result(candidates, inverse_pairs \\ []) do
    %{
      candidates: candidates,
      inverse_pairs: inverse_pairs,
      total_functions: 10,
      candidates_count: length(candidates),
      dropped_count: 0,
      purity_counts: %{pure: 10, unknown: 0, impure: 0}
    }
  end

  describe "from_result/1 and to_json/1" do
    test "captures every candidate with its score" do
      baseline = Baseline.from_result(result([candidate("M", :f, 1, 5)]))

      assert Baseline.size(baseline) == 1
      assert baseline.candidates == %{{"M", "f", 1} => 5}
    end

    test "round-trips through JSON" do
      baseline = Baseline.from_result(result([candidate("M", :f, 1, 5)]))
      json = Baseline.to_json(baseline)

      assert {:ok, parsed} = Baseline.parse(Jason.decode!(json))
      assert parsed.candidates == baseline.candidates
    end

    test "serialises to a stable, sorted order" do
      baseline =
        Baseline.from_result(result([candidate("B", :z, 1, 1), candidate("A", :y, 2, 2)]))

      json = Baseline.to_json(baseline)
      decoded = Jason.decode!(json)

      assert Enum.map(decoded["candidates"], & &1["module"]) == ["A", "B"]
    end

    test "records a version and a timestamp" do
      decoded = Baseline.from_result(result([])) |> Baseline.to_json() |> Jason.decode!()

      assert decoded["version"] == 1
      assert is_binary(decoded["generated_at"])
    end
  end

  describe "write/2 and read/2" do
    setup do
      dir = Path.join(System.tmp_dir!(), "propwise_bl_#{System.unique_integer([:positive])}")
      File.mkdir_p!(dir)
      on_exit(fn -> File.rm_rf!(dir) end)
      {:ok, dir: dir}
    end

    test "writes and reads back a baseline", %{dir: dir} do
      path = Path.join([dir, "nested", "baseline.json"])
      baseline = Baseline.from_result(result([candidate("M", :f, 1, 5)]))

      assert :ok = Baseline.write(path, baseline)
      assert {:ok, read} = Baseline.read(path)
      assert read.candidates == baseline.candidates
    end

    test "reading a missing file is an error", %{dir: dir} do
      assert {:error, :enoent} = Baseline.read(Path.join(dir, "nope.json"))
    end

    test "reading malformed JSON is an error", %{dir: dir} do
      path = Path.join(dir, "bad.json")
      File.write!(path, "{not json")

      assert {:error, _} = Baseline.read(path)
    end

    test "reading a structurally invalid baseline is an error", %{dir: dir} do
      path = Path.join(dir, "wrong.json")
      File.write!(path, ~s({"candidates": [{"module": 1}]}))

      assert {:error, {:invalid_entry, _}} = Baseline.read(path)
    end

    test "reading a document without candidates is an error", %{dir: dir} do
      path = Path.join(dir, "empty.json")
      File.write!(path, ~s({"version": 1}))

      assert {:error, {:invalid_baseline, _}} = Baseline.read(path)
    end
  end

  describe "diff/2" do
    test "a candidate absent from the baseline is new" do
      baseline = Baseline.from_result(result([]))
      diff = Baseline.diff(baseline, [candidate("M", :f, 1, 5)])

      assert length(diff.new) == 1
      assert diff.known == []
    end

    test "a candidate present with the same score is known" do
      baseline = Baseline.from_result(result([candidate("M", :f, 1, 5)]))
      diff = Baseline.diff(baseline, [candidate("M", :f, 1, 5)])

      assert diff.new == []
      assert length(diff.known) == 1
    end

    test "a candidate whose score increased is new (a regression)" do
      baseline = Baseline.from_result(result([candidate("M", :f, 1, 5)]))
      diff = Baseline.diff(baseline, [candidate("M", :f, 1, 7)])

      assert length(diff.new) == 1
    end

    test "a candidate whose score decreased is known (an improvement)" do
      baseline = Baseline.from_result(result([candidate("M", :f, 1, 7)]))
      diff = Baseline.diff(baseline, [candidate("M", :f, 1, 5)])

      assert diff.new == []
      assert length(diff.known) == 1
    end

    test "arity is part of a candidate's identity" do
      baseline = Baseline.from_result(result([candidate("M", :f, 1, 5)]))
      diff = Baseline.diff(baseline, [candidate("M", :f, 2, 5)])

      assert length(diff.new) == 1
    end

    test "module is part of a candidate's identity" do
      baseline = Baseline.from_result(result([candidate("A", :f, 1, 5)]))
      diff = Baseline.diff(baseline, [candidate("B", :f, 1, 5)])

      assert length(diff.new) == 1
    end
  end

  describe "apply_to_result/2" do
    test "keeps only new candidates" do
      baseline = Baseline.from_result(result([candidate("M", :old, 1, 5)]))

      filtered =
        Baseline.apply_to_result(
          baseline,
          result([candidate("M", :old, 1, 5), candidate("M", :new, 1, 6)])
        )

      assert Enum.map(filtered.candidates, & &1.name) == [:new]
      assert filtered.candidates_count == 1
    end

    test "recomputes candidates_count" do
      baseline = Baseline.from_result(result([]))

      filtered =
        Baseline.apply_to_result(
          baseline,
          result([candidate("M", :a, 1, 5), candidate("M", :b, 1, 5)])
        )

      assert filtered.candidates_count == 2
    end

    test "drops inverse pairs with no surviving side" do
      baseline =
        Baseline.from_result(
          result([candidate("M", :encode, 1, 5), candidate("M", :decode, 1, 5)])
        )

      pair = %{
        type: :inverse_pair,
        forward: {"M", :encode, 1},
        inverse: {"M", :decode, 1},
        suggestion: "round-trip"
      }

      filtered = Baseline.apply_to_result(baseline, result([], [pair]))

      assert filtered.inverse_pairs == []
    end

    test "keeps an inverse pair when one side survives" do
      baseline = Baseline.from_result(result([candidate("M", :encode, 1, 5)]))

      pair = %{
        type: :inverse_pair,
        forward: {"M", :encode, 1},
        inverse: {"M", :decode, 1},
        suggestion: "round-trip"
      }

      filtered =
        Baseline.apply_to_result(
          baseline,
          result([candidate("M", :decode, 1, 5)], [pair])
        )

      assert length(filtered.inverse_pairs) == 1
    end
  end

  describe "--baseline CLI integration" do
    setup do
      dir = Path.join(System.tmp_dir!(), "propwise_blcli_#{System.unique_integer([:positive])}")
      File.mkdir_p!(Path.join(dir, "lib"))

      File.write!(Path.join(dir, "lib/m.ex"), """
      defmodule M do
        def double_all(list), do: Enum.map(list, &(&1 * 2))
      end
      """)

      on_exit(fn -> File.rm_rf!(dir) end)
      {:ok, dir: dir}
    end

    test "writing a baseline then analysing against it reports no new candidates",
         %{dir: dir} do
      baseline_path = Path.join(dir, "baseline.json")

      assert :ok =
               CommandLine.run_analysis(dir,
                 min_score: 0,
                 write_baseline: baseline_path
               )

      assert File.exists?(baseline_path)

      # With the baseline in place, nothing is new -> exit :ok even though the
      # project still has candidates.
      assert :ok =
               CommandLine.run_analysis(dir,
                 min_score: 0,
                 baseline: baseline_path
               )
    end

    test "a newly introduced candidate is reported against the baseline", %{dir: dir} do
      baseline_path = Path.join(dir, "baseline.json")

      :ok = CommandLine.run_analysis(dir, min_score: 0, write_baseline: baseline_path)

      File.write!(Path.join(dir, "lib/n.ex"), """
      defmodule N do
        def filter_positive(list), do: Enum.filter(list, &(&1 > 0))
      end
      """)

      assert {:suggestions_found, count} =
               CommandLine.run_analysis(dir, min_score: 0, baseline: baseline_path)

      assert count == 1
    end

    test "an unreadable baseline is an error, not a silent empty baseline", %{dir: dir} do
      bad = Path.join(dir, "bad.json")
      File.write!(bad, "{not json")

      parent = self()

      result =
        CommandLine.run_analysis(dir, [min_score: 0, baseline: bad],
          error: fn m -> send(parent, {:err, m}) end
        )

      assert {:error, message} = result
      assert message =~ "cannot read baseline"
      assert_received {:err, _}
    end
  end
end
