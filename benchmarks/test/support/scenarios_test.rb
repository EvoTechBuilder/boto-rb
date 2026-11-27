# frozen_string_literal: true

require "stringio"
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
    without_redis do
      with_data do
        assert_equal ["boto"], BenchScenarios.frameworks_for("db_schema")
        assert_equal %w[db_schema db_auth db_repository], BenchScenarios.scenarios_for("boto") - %w[hello db]
        assert_equal %w[hello db], BenchScenarios.scenarios_for("roda")
      end
    end
  end

  def test_db_auth_runs_only_on_boto
    assert_equal ["boto"], BenchScenarios.frameworks_for("db_auth")
    assert_equal %w[hello db], BenchScenarios.scenarios_for("roda")
  end

  def test_combinations_skip_unsupported_pairs
    without_redis do
      with_data do
        combinations = BenchScenarios.combinations
        assert_includes combinations, ["boto", "db_schema"]
        assert_includes combinations, ["boto", "db_auth"]
        assert_includes combinations, ["boto", "db_repository"]
        refute_includes combinations, ["roda", "db_schema"]
        refute_includes combinations, ["sinatra", "db_auth"]
        refute_includes combinations, ["roda", "db_repository"]
        assert_equal 9, combinations.size
      end
    end
  end

  def test_combinations_include_db_auth_redis_only_with_redis
    without_redis { refute_includes BenchScenarios.combinations, ["boto", "db_auth_redis"] }
    with_redis do
      with_data do
        assert_includes BenchScenarios.combinations, ["boto", "db_auth_redis"]
        assert_equal 10, BenchScenarios.combinations.size
      end
    end
  end

  def test_db_schema_is_a_db_scenario_with_the_same_paths
    assert BenchScenarios.db_scenario?("db_schema")
    assert_equal "/users/500", BenchScenarios.load_path("db_schema")
    assert_equal "/users/1", BenchScenarios.path_for("db_schema", 0)
    assert File.exist?(BenchScenarios.app_path("boto", "db_schema"))
  end

  def test_db_auth_is_a_db_scenario_with_the_same_paths
    assert BenchScenarios.db_scenario?("db_auth")
    assert_equal "/users/500", BenchScenarios.load_path("db_auth")
    assert_equal "/users/1", BenchScenarios.path_for("db_auth", 0)
    assert File.exist?(BenchScenarios.app_path("boto", "db_auth"))
  end

  def test_db_auth_redis_is_a_db_scenario_with_its_own_app
    assert BenchScenarios.db_scenario?("db_auth_redis")
    assert_equal "/users/500", BenchScenarios.load_path("db_auth_redis")
    assert_equal "/users/1", BenchScenarios.path_for("db_auth_redis", 0)
    assert File.exist?(BenchScenarios.app_path("boto", "db_auth_redis"))
  end

  def test_db_repository_is_a_db_scenario_with_its_own_app
    assert BenchScenarios.db_scenario?("db_repository")
    assert_equal "/users/500", BenchScenarios.load_path("db_repository")
    assert_equal "/users/1", BenchScenarios.path_for("db_repository", 0)
    assert File.exist?(BenchScenarios.app_path("boto", "db_repository"))
  end

  def test_db_auth_redis_runs_only_on_boto_when_redis_is_available
    with_redis do
      with_data do
        assert_equal ["boto"], BenchScenarios.frameworks_for("db_auth_redis")
        assert_equal %w[hello db db_schema db_auth db_auth_redis db_repository], BenchScenarios.scenarios_for("boto")
      end
    end
  end

  def test_db_auth_redis_is_left_out_without_redis
    without_redis do
      assert_empty BenchScenarios.frameworks_for("db_auth_redis")
      refute_includes BenchScenarios.scenarios_for("boto"), "db_auth_redis"
    end
  end

  def test_db_repository_runs_only_on_boto_when_data_gem_is_present
    with_data do
      assert_equal ["boto"], BenchScenarios.frameworks_for("db_repository")
      assert_includes BenchScenarios.scenarios_for("boto"), "db_repository"
    end
  end

  def test_db_repository_is_left_out_without_data_gem
    without_data do
      assert_empty BenchScenarios.frameworks_for("db_repository")
      refute_includes BenchScenarios.scenarios_for("boto"), "db_repository"
      refute_includes BenchScenarios.combinations, ["boto", "db_repository"]
    end
  end

  def test_only_db_auth_scenarios_send_authorization_header
    assert_equal({ "Authorization" => "Bearer bench-token" }, BenchScenarios.headers_for("db_auth"))
    assert_equal({ "HTTP_AUTHORIZATION" => "Bearer bench-token" }, BenchScenarios.rack_env_for("db_auth"))
    assert_equal({ "HTTP_AUTHORIZATION" => "Bearer bench-token" }, BenchScenarios.rack_env_for("db_auth_redis"))
    assert_empty BenchScenarios.headers_for("db")
    assert_empty BenchScenarios.headers_for("hello")
    assert_empty BenchScenarios.rack_env_for("db_schema")
    assert_empty BenchScenarios.rack_env_for("db_repository")
  end

  def test_matrix_holds_only_supported_combinations
    without_redis do
      with_data do
        matrix = BenchScenarios.matrix { |framework, scenario| "#{framework}/#{scenario}" }
        assert_equal({ "hello" => "boto/hello", "db" => "boto/db", "db_schema" => "boto/db_schema",
                       "db_auth" => "boto/db_auth", "db_repository" => "boto/db_repository" }, matrix["boto"])
        assert_equal({ "hello" => "roda/hello", "db" => "roda/db" }, matrix["roda"])
        assert_equal BenchScenarios::FRAMEWORKS, matrix.keys
      end
    end
  end

  def test_matrix_includes_db_auth_redis_with_redis
    with_redis do
      matrix = BenchScenarios.matrix { |framework, scenario| "#{framework}/#{scenario}" }
      assert_equal "boto/db_auth_redis", matrix["boto"]["db_auth_redis"]
      refute_includes matrix["roda"].keys, "db_auth_redis"
    end
  end

  def test_redis_url_uses_env_or_default
    assert_equal BenchScenarios::REDIS_DEFAULT_URL, BenchScenarios.redis_url(env: {})
    assert_equal "redis://10.0.0.5:6390/1", BenchScenarios.redis_url(env: { "REDIS_URL" => "redis://10.0.0.5:6390/1" })
  end

  def test_boto_root_uses_env_or_the_repo_root
    assert_equal "/checkout/boto", BenchScenarios.boto_root(env: { "BOTO_ROOT" => "/checkout/boto" })
    assert_equal File.expand_path("..", BenchScenarios::ROOT), BenchScenarios.boto_root(env: {})
  end

  def test_redis_endpoint_shows_only_host_and_port
    assert_equal "10.0.0.5:6390", BenchScenarios.redis_endpoint("redis://:secret@10.0.0.5:6390/0")
    assert_equal "127.0.0.1:6379", BenchScenarios.redis_endpoint("redis://127.0.0.1/0")
    assert_equal "invalid REDIS_URL", BenchScenarios.redis_endpoint("redis://bad host/0")
  end

  def test_redis_reachable_is_false_when_nothing_listens
    refute BenchScenarios.redis_reachable?("redis://127.0.0.1:1/0")
  end

  def test_redis_skip_notice_is_nil_with_redis
    with_redis { assert_nil BenchScenarios.redis_skip_notice }
  end

  def test_warn_skipped_prints_one_line_without_redis
    out = StringIO.new
    without_redis { with_data { BenchScenarios.warn_skipped(io: out) } }
    assert_match(/\Adb_auth_redis skipped: Redis not available at \S+:\d+\n\z/, out.string)
  end

  def test_warn_skipped_names_db_repository_without_data_gem
    out = StringIO.new
    with_redis { without_data { BenchScenarios.warn_skipped(io: out) } }
    assert_equal "db_repository skipped: gems/boto-rb-data not found\n", out.string
  end

  def test_warn_skipped_is_silent_with_redis_and_data
    out = StringIO.new
    with_redis { with_data { BenchScenarios.warn_skipped(io: out) } }
    assert_empty out.string
  end
end
