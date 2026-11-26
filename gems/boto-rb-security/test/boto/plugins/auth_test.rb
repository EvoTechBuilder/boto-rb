# frozen_string_literal: true

require "test_helper"
require "rack/mock"
require "json"

class Boto::Plugins::AuthTest < Minitest::Test
  AUTH = Boto::Plugins::Auth
  PRINCIPAL_APP = ->(env) { [200, {}, [env[AUTH::PRINCIPAL_KEY].inspect]] }
  FORBIDDEN_APP = ->(_env) { raise "app must not run when auth fails" }

  def test_scope_and_plugin_name
    assert_equal :endpoint, AUTH.scope
    assert_equal :auth, AUTH.plugin_name
  end

  def test_unknown_strategy_raises
    error = assert_raises(ArgumentError) { build(strategy: :nope) }

    assert_equal "unknown auth strategy :nope", error.message
  end

  def test_invalid_strategy_name_raises
    assert_raises(ArgumentError) { build(strategy: "Basic") }
    assert_raises(ArgumentError) { build(strategy: :"api-key") }
  end

  def test_resolves_strategy_class_from_name
    assert_instance_of AUTH::Basic, build(strategy: :basic, credentials: { "admin" => "s3cret" }).strategy
    assert_instance_of AUTH::Bearer, build(strategy: :bearer, tokens: ["t"]).strategy
    assert_instance_of AUTH::ApiKey, build(strategy: :api_key, keys: { "ci" => "k" }).strategy
  end

  def test_success_stores_principal_and_calls_app
    status, _headers, body = build(strategy: :basic, credentials: { "admin" => "s3cret" }).call(
      env_with("Basic YWRtaW46czNjcmV0"), PRINCIPAL_APP
    )

    assert_equal 200, status
    assert_equal({ user: "admin" }.inspect, body.first)
  end

  def test_failure_returns_401_without_details
    status, headers, body = build(strategy: :basic, credentials: { "admin" => "s3cret" }).call(
      env_with("Basic YWRtaW46d3Jvbmc="), FORBIDDEN_APP
    )

    assert_equal 401, status
    assert_equal 'Basic realm="Boto"', headers["www-authenticate"]
    assert_equal "application/problem+json", headers["content-type"]
    assert_equal({ "type" => "about:blank", "title" => "Unauthorized", "status" => 401 }, JSON.parse(body.join))
  end

  def test_exposes_strategy_object
    plugin = build(strategy: :bearer, tokens: ["t"])

    assert_instance_of AUTH::Bearer, plugin.strategy
    assert_equal 'Bearer realm="Boto"', plugin.strategy.challenge
  end

  def test_error_statuses_are_401_for_a_strategy_without_error_statuses
    assert_equal [401], build(strategy: :bearer, tokens: ["t"]).error_statuses
  end

  def test_error_statuses_add_the_statuses_of_the_strategy
    plugin = build(strategy: :bearer, tokens: ["t"])
    strategy = Object.new
    strategy.define_singleton_method(:error_statuses) { [413] }
    plugin.define_singleton_method(:strategy) { strategy }

    assert_equal [401, 413], plugin.error_statuses
  end

  private

  def build(**options)
    AUTH.new(env_name: "production", **options)
  end

  def env_with(header)
    Rack::MockRequest.env_for("/", "HTTP_AUTHORIZATION" => header)
  end
end
