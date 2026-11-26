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
end
