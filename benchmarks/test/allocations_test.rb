# frozen_string_literal: true

require_relative "test_helper"
require_relative "../allocations"

class BenchAllocationsTest < Minitest::Test
  def test_allocations_for_counts_objects_of_one_call
    app = ->(_env) { [200, {}, ["ok"]] }
    env = Rack::MockRequest.env_for("/")
    assert_kind_of Integer, BenchAllocations.allocations_for(app, env)
    assert_operator BenchAllocations.allocations_for(app, env), :>=, 0
  end

  def test_build_envs_spreads_db_paths
    envs = BenchAllocations.build_envs("db", 3, offset: 0)
    assert_equal ["/users/1", "/users/2", "/users/3"], envs.map { _1["PATH_INFO"] }
  end

  def test_build_envs_spreads_db_schema_paths
    envs = BenchAllocations.build_envs("db_schema", 2, offset: 0)
    assert_equal ["/users/1", "/users/2"], envs.map { _1["PATH_INFO"] }
  end

  def test_build_envs_spreads_db_repository_paths
    envs = BenchAllocations.build_envs("db_repository", 2, offset: 0)
    assert_equal ["/users/1", "/users/2"], envs.map { _1["PATH_INFO"] }
  end

  def test_build_envs_sends_bearer_token_only_for_db_auth
    auth_envs = BenchAllocations.build_envs("db_auth", 2, offset: 0)
    assert_equal ["Bearer bench-token"] * 2, auth_envs.map { _1["HTTP_AUTHORIZATION"] }
    redis_envs = BenchAllocations.build_envs("db_auth_redis", 2, offset: 0)
    assert_equal ["Bearer bench-token"] * 2, redis_envs.map { _1["HTTP_AUTHORIZATION"] }
    assert_nil BenchAllocations.build_envs("db", 1, offset: 0).first["HTTP_AUTHORIZATION"]
  end
end
