# frozen_string_literal: true

require_relative "../test_helper"
require "json"

# Each .ru is loaded once per process, since loading it again redefines its routes.
class BenchAppsTest < Minitest::Test
  LOADED = {}

  def app(framework, scenario)
    LOADED[[framework, scenario]] ||= Rack::Builder.parse_file(BenchScenarios.app_path(framework, scenario))
  end

  # Sends the scenario's own headers (e.g. the bearer token of db_auth) unless the test passes others.
  def get(framework, scenario, path, extra_env: BenchScenarios.rack_env_for(scenario))
    status, headers, body = app(framework, scenario).call(Rack::MockRequest.env_for(path, extra_env))
    text = +""
    body.each { text << _1 }
    body.close if body.respond_to?(:close)
    [status, headers["content-type"], text]
  end

  BenchScenarios.combinations.select { |_framework, scenario| scenario == "hello" }.each do |framework, _scenario|
    define_method("test_#{framework}_hello_returns_json") do
      status, type, text = get(framework, "hello", "/")
      assert_equal 200, status
      assert_match %r{application/json}, type
      assert_equal({ "hello" => "world" }, JSON.parse(text))
    end
  end

  BenchScenarios.combinations.select { |_framework, scenario| BenchScenarios.db_scenario?(scenario) }.each do |framework, scenario|
    define_method("test_#{framework}_#{scenario}_returns_user") do
      status, type, text = get(framework, scenario, BenchScenarios::DB_LOAD_PATH)
      assert_equal 200, status
      assert_match %r{application/json}, type
      assert_equal({ "id" => 500, "name" => "user 500" }, JSON.parse(text))
    end

    define_method("test_#{framework}_#{scenario}_missing_user_is_404") do
      status, _type, _text = get(framework, scenario, "/users/99999")
      assert_equal 404, status
    end
  end

  def test_boto_db_auth_with_token_returns_user
    status, _type, text = get("boto", "db_auth", BenchScenarios::DB_LOAD_PATH)
    assert_equal 200, status
    assert_equal({ "id" => 500, "name" => "user 500" }, JSON.parse(text))
  end

  def test_boto_db_auth_without_token_is_401
    status, _type, _text = get("boto", "db_auth", BenchScenarios::DB_LOAD_PATH, extra_env: {})
    assert_equal 401, status
  end

  def test_boto_db_auth_redis_with_token_returns_user
    skip "Redis não disponível" unless BenchScenarios.redis_available?

    status, _type, text = get("boto", "db_auth_redis", BenchScenarios::DB_LOAD_PATH)
    assert_equal 200, status
    assert_equal({ "id" => 500, "name" => "user 500" }, JSON.parse(text))
  end

  def test_boto_db_auth_redis_without_token_is_401
    skip "Redis não disponível" unless BenchScenarios.redis_available?

    status, _type, _text = get("boto", "db_auth_redis", BenchScenarios::DB_LOAD_PATH, extra_env: {})
    assert_equal 401, status
  end
end
