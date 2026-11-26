# frozen_string_literal: true

require "test_helper"
require "rack/mock"

class Boto::Plugins::CorsTest < Minitest::Test
  ORIGIN = "https://painel.loja.com"
  OTHER_ORIGIN = "https://evil.example"

  def test_scope_and_plugin_name
    assert_equal :global, Boto::Plugins::Cors.scope
    assert_equal :cors, Boto::Plugins::Cors.plugin_name
  end

  def test_request_without_origin_passes_app_response_untouched
    headers = { "content-type" => "text/plain" }
    status, response_headers, = plugin(origins: [ORIGIN]).call(env_for, app(headers))

    assert_equal 200, status
    assert_same headers, response_headers
  end

  def test_allowed_preflight_answers_204_without_calling_app
    calls = []
    status, headers, body = plugin(origins: [ORIGIN], max_age: 600, credentials: true)
                            .call(preflight_env(ORIGIN, "QUERY"), recording_app(calls))

    assert_equal 204, status
    assert_equal [], body
    assert_empty calls
    assert_equal ORIGIN, headers["access-control-allow-origin"]
    assert_includes headers["access-control-allow-methods"].split(", "), "QUERY"
    assert_equal "content-type, authorization", headers["access-control-allow-headers"]
    assert_equal "600", headers["access-control-max-age"]
    assert_equal "true", headers["access-control-allow-credentials"]
    assert_equal "Origin", headers["vary"]
  end

  def test_preflight_from_disallowed_origin_is_forbidden
    status, = plugin(origins: [ORIGIN]).call(preflight_env(OTHER_ORIGIN, "GET"), recording_app([]))

    assert_equal 403, status
  end

  def test_preflight_with_disallowed_method_is_forbidden
    status, = plugin(origins: [ORIGIN]).call(preflight_env(ORIGIN, "TRACE"), recording_app([]))

    assert_equal 403, status
  end

  def test_allowed_request_gets_cors_headers_and_merged_vary
    response_headers = { "vary" => "Accept-Encoding" }
    _, headers, = plugin(origins: [ORIGIN], expose: %w[x-request-id], credentials: true)
                  .call(request_env(ORIGIN), app(response_headers))

    assert_equal ORIGIN, headers["access-control-allow-origin"]
    assert_equal "x-request-id", headers["access-control-expose-headers"]
    assert_equal "true", headers["access-control-allow-credentials"]
    assert_equal "Accept-Encoding, Origin", headers["vary"]
  end

  def test_vary_origin_is_not_duplicated
    _, headers, = plugin(origins: [ORIGIN]).call(request_env(ORIGIN), app({ "vary" => "origin" }))

    assert_equal "origin", headers["vary"]
  end

  def test_frozen_response_headers_are_duplicated_before_changes
    frozen = { "content-type" => "text/plain" }.freeze
    _, headers, = plugin(origins: [ORIGIN]).call(request_env(ORIGIN), app(frozen))

    assert_equal ORIGIN, headers["access-control-allow-origin"]
    refute_includes frozen.keys, "access-control-allow-origin"
  end

  def test_disallowed_origin_on_normal_request_gets_no_cors_headers
    status, headers, = plugin(origins: [ORIGIN]).call(request_env(OTHER_ORIGIN), app({}))

    assert_equal 200, status
    refute_includes headers.keys, "access-control-allow-origin"
    refute_includes headers.keys, "vary"
  end

  def test_wildcard_origin_without_credentials_answers_star
    _, normal_headers, = plugin(origins: "*").call(request_env(OTHER_ORIGIN), app({}))
    _, preflight_headers, = plugin(origins: "*").call(preflight_env(OTHER_ORIGIN, "GET"), recording_app([]))

    assert_equal "*", normal_headers["access-control-allow-origin"]
    assert_equal "*", preflight_headers["access-control-allow-origin"]
  end

  def test_wildcard_origin_with_credentials_is_rejected
    error = assert_raises(ArgumentError) { plugin(origins: "*", credentials: true) }

    assert_equal 'cors: origins "*" cannot be used with credentials', error.message
  end

  def test_invalid_max_age_is_rejected
    [-1, "600", 1.5].each do |max_age|
      assert_raises(ArgumentError) { plugin(origins: [ORIGIN], max_age: max_age) }
    end
  end

  def test_configured_origins_are_normalized_to_lowercase
    status, headers, = plugin(origins: ["https://Painel.Loja.com"]).call(
      Rack::MockRequest.env_for("/", "HTTP_ORIGIN" => "https://painel.loja.com"), ->(_env) { [200, {}, []] }
    )
    assert_equal 200, status
    assert_equal "https://painel.loja.com", headers["access-control-allow-origin"]
  end

  def test_invalid_origins_raise
    assert_raises(ArgumentError) { plugin(origins: ["*"]) }
    assert_raises(ArgumentError) { plugin(origins: [""]) }
    assert_raises(ArgumentError) { plugin(origins: ORIGIN) }
  end

  private

  def plugin(**options)
    Boto::Plugins::Cors.new(env_name: "production", **options)
  end

  def env_for(**options)
    Rack::MockRequest.env_for("/orders", options)
  end

  def request_env(origin)
    env_for(method: "GET", "HTTP_ORIGIN" => origin)
  end

  def preflight_env(origin, requested_method)
    env_for(method: "OPTIONS", "HTTP_ORIGIN" => origin, "HTTP_ACCESS_CONTROL_REQUEST_METHOD" => requested_method)
  end

  def app(headers)
    ->(_env) { [200, headers, ["ok"]] }
  end

  def recording_app(calls)
    lambda do |env|
      calls << env
      [200, {}, ["ok"]]
    end
  end
end
