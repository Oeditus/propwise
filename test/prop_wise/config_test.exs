defmodule PropWise.ConfigTest do
  use ExUnit.Case, async: true

  alias PropWise.Config

  describe "load/1" do
    test "returns default config when .propwise.exs doesn't exist" do
      test_dir = "/tmp/propwise_config_test_#{System.unique_integer([:positive])}"
      File.mkdir_p!(test_dir)

      config = Config.load(test_dir)

      File.rm_rf!(test_dir)

      assert config.analyze_paths == ["lib"]
    end

    test "loads config from .propwise.exs when it exists" do
      test_dir = "/tmp/propwise_config_test_#{System.unique_integer([:positive])}"
      File.mkdir_p!(test_dir)

      config_file = Path.join(test_dir, ".propwise.exs")

      File.write!(config_file, """
      %{
        analyze_paths: ["lib", "src"]
      }
      """)

      config = Config.load(test_dir)

      File.rm_rf!(test_dir)

      assert config.analyze_paths == ["lib", "src"]
    end

    test "handles keyword list configuration" do
      test_dir = "/tmp/propwise_config_test_#{System.unique_integer([:positive])}"
      File.mkdir_p!(test_dir)

      config_file = Path.join(test_dir, ".propwise.exs")

      File.write!(config_file, """
      [
        analyze_paths: ["lib", "apps"]
      ]
      """)

      config = Config.load(test_dir)

      File.rm_rf!(test_dir)

      assert config.analyze_paths == ["lib", "apps"]
    end

    test "returns default config on invalid configuration" do
      test_dir = "/tmp/propwise_config_test_#{System.unique_integer([:positive])}"
      File.mkdir_p!(test_dir)

      config_file = Path.join(test_dir, ".propwise.exs")

      File.write!(config_file, """
      "invalid config"
      """)

      config = Config.load(test_dir)

      File.rm_rf!(test_dir)

      assert config.analyze_paths == ["lib"]
    end
  end

  describe "analyze_paths/1" do
    test "returns configured paths" do
      test_dir = "/tmp/propwise_config_test_#{System.unique_integer([:positive])}"
      File.mkdir_p!(test_dir)

      config_file = Path.join(test_dir, ".propwise.exs")

      File.write!(config_file, """
      %{
        analyze_paths: ["custom_lib"]
      }
      """)

      paths = Config.analyze_paths(test_dir)

      File.rm_rf!(test_dir)

      assert paths == ["custom_lib"]
    end

    test "returns default paths when no config file exists" do
      test_dir = "/tmp/propwise_config_test_#{System.unique_integer([:positive])}"
      File.mkdir_p!(test_dir)

      paths = Config.analyze_paths(test_dir)

      File.rm_rf!(test_dir)

      assert paths == ["lib"]
    end
  end
end
