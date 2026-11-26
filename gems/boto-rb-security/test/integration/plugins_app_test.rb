# frozen_string_literal: true

require "test_helper"
require "rack/mock"
require "stringio"
require "openssl"

module PluginsAppShop
  class Me < Boto::Endpoint
    get "/me"
    def call = principal
  end

  class Health < Boto::Endpoint
    get "/health"
    skip :auth, :rate_limit
    def call = { status: "ok" }
  end

  class Webhook < Boto::Endpoint
    post "/webhook"
    authenticate :signature, secret: "s3", header: "X-Signature"
    def call = { received: true }
  end
end

class PluginsAppTest < Minitest::Test
  HOST = "api.test"
  ORIGIN = "https://app.test"
  TOKEN = "t0k"
  REMOTE = "10.0.0.1"
  BEARER = { "HTTP_AUTHORIZATION" => "Bearer #{TOKEN}" }.freeze

  def setup
    @error_output = StringIO.new
    @app = build_app
  end

  def build_app
    config = Boto::Configuration.new(env_name: "production")
                                .use(:hosts, allow: [HOST])
                                .use(:cors, origins: [ORIGIN])
                                .use(:auth, strategy: :bearer, tokens: [TOKEN])
                                .use(:rate_limit, limit: 2, period: 60, clock: -> { 0 })
    Boto::App.new(namespace: PluginsAppShop, plugins: config.plugins, env_name: "production",
                  error_output: @error_output)
  end

  def send_request(verb, path, headers = {}, body = "")
    env = { "HTTP_HOST" => HOST, "REMOTE_ADDR" => REMOTE, input: body }.merge(headers)
    Rack::MockRequest.new(@app).request(verb, path, env)
  end

  def sign(body, secret)
    OpenSSL::HMAC.hexdigest("sha256", secret, body)
  end

  def test_preflight_is_answered_without_token
    res = send_request("OPTIONS", "/me", "HTTP_ORIGIN" => ORIGIN, "HTTP_ACCESS_CONTROL_REQUEST_METHOD" => "GET")

    assert_equal 204, res.status
    assert_equal ORIGIN, res.headers["access-control-allow-origin"]
  end

  def test_unknown_route_from_allowed_origin_keeps_cors_header
    res = send_request("GET", "/nope", "HTTP_ORIGIN" => ORIGIN)

    assert_equal 404, res.status
    assert_equal ORIGIN, res.headers["access-control-allow-origin"]
  end

  def test_host_not_allowed_is_rejected_before_routing
    res = send_request("GET", "/nope", "HTTP_HOST" => "evil.test")

    assert_equal 403, res.status
  end

  def test_endpoint_without_token_returns_401
    assert_equal 401, send_request("GET", "/me").status
  end

  def test_endpoint_with_bearer_receives_principal
    res = send_request("GET", "/me", BEARER)

    assert_equal 200, res.status
    assert_equal({ "token_index" => 0 }, JSON.parse(res.body))
  end

  def test_skipped_endpoint_answers_without_token_and_does_not_count_for_rate_limit
    3.times { assert_equal 200, send_request("GET", "/health").status }

    assert_equal 200, send_request("GET", "/me", BEARER).status
    assert_equal 200, send_request("GET", "/me", BEARER).status
  end

  def test_third_authenticated_request_is_rate_limited
    2.times { send_request("GET", "/me", BEARER) }

    assert_equal 429, send_request("GET", "/me", BEARER).status
  end

  def test_signature_endpoint_accepts_valid_hmac_without_bearer
    body = '{"event":"paid"}'
    res = send_request("POST", "/webhook", { "HTTP_X_SIGNATURE" => sign(body, "s3") }, body)

    assert_equal 200, res.status
  end

  def test_signature_endpoint_rejects_wrong_hmac
    body = '{"event":"paid"}'
    res = send_request("POST", "/webhook", { "HTTP_X_SIGNATURE" => sign(body, "wrong") }, body)

    assert_equal 401, res.status
  end

  def test_auth_for_returns_the_endpoint_strategy
    assert_instance_of Boto::Plugins::Auth::Bearer, @app.auth_for(PluginsAppShop::Me).strategy
    assert_instance_of Boto::Plugins::Auth::Signature, @app.auth_for(PluginsAppShop::Webhook).strategy
  end

  def test_auth_for_skipped_endpoint_is_nil
    assert_nil @app.auth_for(PluginsAppShop::Health)
  end
end
