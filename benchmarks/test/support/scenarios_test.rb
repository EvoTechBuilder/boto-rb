# frozen_string_literal: true

require_relative "../test_helper"

class BenchScenariosTest < Minitest::Test
  def test_app_path_points_to_the_ru_file
    expected = File.join(BenchScenarios::ROOT, "apps", "roda", "db.ru")
    assert_equal expected, BenchScenarios.app_path("roda", "db")
    assert File.exist?(expected)
  end

  def test_hello_always_uses_root
    assert_equal "/", BenchScenarios.path_for("hello", 42)
    assert_equal "/", BenchScenarios.load_path("hello")
  end

  def test_db_paths_cycle_over_seeded_users
    assert_equal "/users/1", BenchScenarios.path_for("db", 0)
    assert_equal "/users/1", BenchScenarios.path_for("db", BenchDatabase::USER_COUNT)
  end

  def test_db_load_path_is_fixed
    assert_equal "/users/500", BenchScenarios.load_path("db")
  end

  def test_hello_and_db_run_on_every_framework
    assert_equal BenchScenarios::FRAMEWORKS, BenchScenarios.frameworks_for("hello")
    assert_equal BenchScenarios::FRAMEWORKS, BenchScenarios.frameworks_for("db")
  end

  def test_db_schema_runs_only_on_boto
    assert_equal ["boto"], BenchScenarios.frameworks_for("db_schema")
    assert_equal ["db_schema"], BenchScenarios.scenarios_for("boto") - %w[hello db]
    assert_equal %w[hello db], BenchScenarios.scenarios_for("roda")
  end

  def test_combinations_skip_unsupported_pairs
    combinations = BenchScenarios.combinations
    assert_includes combinations, ["boto", "db_schema"]
    refute_includes combinations, ["roda", "db_schema"]
    refute_includes combinations, ["sinatra", "db_schema"]
    assert_equal 7, combinations.size
  end

  def test_db_schema_is_a_db_scenario_with_the_same_paths
    assert BenchScenarios.db_scenario?("db_schema")
    assert_equal "/users/500", BenchScenarios.load_path("db_schema")
    assert_equal "/users/1", BenchScenarios.path_for("db_schema", 0)
    assert File.exist?(BenchScenarios.app_path("boto", "db_schema"))
  end

  def test_matrix_holds_only_supported_combinations
    matrix = BenchScenarios.matrix { |framework, scenario| "#{framework}/#{scenario}" }
    assert_equal({ "hello" => "boto/hello", "db" => "boto/db", "db_schema" => "boto/db_schema" }, matrix["boto"])
    assert_equal({ "hello" => "roda/hello", "db" => "roda/db" }, matrix["roda"])
    assert_equal BenchScenarios::FRAMEWORKS, matrix.keys
  end
end
