# frozen_string_literal: true

require "test_helper"
require "rack/mock"
require "securerandom"
require "socket"
require "stringio"

module RedisRateLimitShop
  class Ping < Boto::Endpoint
    get "/ping"
    def call = { ok: true }
  end
end

class RateLimitStoreIntegrationTest < Minitest::Test
  REMOTE = "10.0.0.1"
  LIMIT = 2
  PERIOD = 60

  def setup
    @url = redis_url_or_skip
    @prefix = "boto:test:#{SecureRandom.hex(4)}"
    @redis = ::RedisClient.new(url: @url)
  end

  def teardown
    @redis&.scan("MATCH", "#{@prefix}:*")&.each_slice(100) { |keys| @redis.call("DEL", *keys) }
    @redis&.close
  end

  def test_answers_200_then_429_through_redis
    app = build_app(Boto::Redis::RateLimitStore.new(url: @url, prefix: @prefix))

    assert_equal [200, 200, 429], Array.new(3) { get_status(app) }
  end

  def test_answers_503_when_redis_is_unreachable_and_on_error_is_deny
    store = Boto::Redis::RateLimitStore.new(url: "redis://127.0.0.1:#{closed_port}/0", timeout: 0.05,
                                            on_error: :deny, logger: StringIO.new)

    assert_equal 503, get_status(build_app(store))
  end

  def test_healthy_against_a_real_redis
    store = Boto::Redis::RateLimitStore.new(url: @url)

    assert store.healthy?
  ensure
    store&.close
  end

  private

  def build_app(store)
    config = Boto::Configuration.new(env_name: "production")
                                .use(:rate_limit, limit: LIMIT, period: PERIOD, store: store)
    Boto::App.new(namespace: RedisRateLimitShop, plugins: config.plugins, env_name: "production",
                  error_output: StringIO.new)
  end

  def get_status(app)
    Rack::MockRequest.new(app).get("/ping", "REMOTE_ADDR" => REMOTE).status
  end

  # A port nobody listens on, so connecting fails at once without touching the network.
  def closed_port
    server = TCPServer.new("127.0.0.1", 0)
    server.addr[1].tap { server.close }
  end
end
