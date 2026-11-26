# frozen_string_literal: true

require "test_helper"
require "rack/mock"
require "json"

class Boto::Plugins::RateLimitTest < Minitest::Test
  OK_APP = ->(_env) { [200, { "content-type" => "text/plain" }, ["ok"]] }
  LIMIT = 2
  PERIOD = 60

  class FailingStore
    def initialize(error)
      @error = error
    end

    def increment(_key, _period)
      raise @error
    end
  end

  def setup
    @now = 0.0
    @clock = -> { @now }
  end

  def test_scope_and_plugin_name
    assert_equal :endpoint, Boto::Plugins::RateLimit.scope
    assert_equal :rate_limit, Boto::Plugins::RateLimit.plugin_name
  end

  def test_allows_requests_within_the_limit_with_rate_headers
    plugin = build_plugin

    first = get(plugin)
    assert_equal 200, first.status
    assert_rate_headers(first, limit: LIMIT, remaining: 1, reset: PERIOD)

    second = get(plugin)
    assert_equal 200, second.status
    assert_rate_headers(second, limit: LIMIT, remaining: 0, reset: PERIOD)
  end

  def test_rejects_requests_over_the_limit_with_429_and_retry_after
    plugin = build_plugin
    2.times { get(plugin) }

    response = get(plugin)
    assert_equal 429, response.status
    assert_equal PERIOD.to_s, response.headers["retry-after"]
    assert_includes response.headers["content-type"], "problem+json"
    assert_rate_headers(response, limit: LIMIT, remaining: 0, reset: PERIOD)
  end

  def test_releases_requests_when_the_window_changes
    plugin = build_plugin
    3.times { get(plugin) }

    @now = PERIOD.to_f
    assert_equal 200, get(plugin).status
  end

  def test_counts_each_client_ip_separately
    plugin = build_plugin
    2.times { get(plugin, "REMOTE_ADDR" => "203.0.113.1") }

    assert_equal 429, get(plugin, "REMOTE_ADDR" => "203.0.113.1").status
    assert_equal 200, get(plugin, "REMOTE_ADDR" => "203.0.113.2").status
  end

  def test_uses_custom_key
    plugin = build_plugin(key: ->(env) { env["HTTP_X_API_KEY"] })
    2.times { get(plugin, "HTTP_X_API_KEY" => "a", "REMOTE_ADDR" => "203.0.113.1") }

    assert_equal 429, get(plugin, "HTTP_X_API_KEY" => "a", "REMOTE_ADDR" => "203.0.113.9").status
    assert_equal 200, get(plugin, "HTTP_X_API_KEY" => "b", "REMOTE_ADDR" => "203.0.113.1").status
  end

  def test_ignores_forwarded_for_without_trusted_proxies
    plugin = build_plugin
    2.times { get(plugin, "REMOTE_ADDR" => "10.1.2.3", "HTTP_X_FORWARDED_FOR" => "198.51.100.1") }

    assert_equal 429, get(plugin, "REMOTE_ADDR" => "10.1.2.3", "HTTP_X_FORWARDED_FOR" => "198.51.100.2").status
  end

  def test_ignores_forwarded_for_when_remote_address_is_not_trusted
    plugin = build_plugin(trusted_proxies: ["10.0.0.0/8"])
    2.times { get(plugin, "REMOTE_ADDR" => "203.0.113.1", "HTTP_X_FORWARDED_FOR" => "198.51.100.1") }

    assert_equal 429, get(plugin, "REMOTE_ADDR" => "203.0.113.1", "HTTP_X_FORWARDED_FOR" => "198.51.100.2").status
  end

  def test_uses_rightmost_untrusted_forwarded_ip_for_trusted_cidr
    plugin = build_plugin(trusted_proxies: ["10.0.0.0/8"])
    forwarded = { "REMOTE_ADDR" => "10.1.2.3", "HTTP_X_FORWARDED_FOR" => "198.51.100.9, 10.9.9.9" }
    2.times { get(plugin, forwarded) }

    assert_equal 429, get(plugin, forwarded).status
    assert_equal 200, get(plugin, "REMOTE_ADDR" => "10.1.2.3", "HTTP_X_FORWARDED_FOR" => "203.0.113.5").status
  end

  def test_uses_rightmost_untrusted_forwarded_ip_for_single_address_proxy
    plugin = build_plugin(trusted_proxies: ["192.168.1.1"])
    2.times { get(plugin, "REMOTE_ADDR" => "192.168.1.1", "HTTP_X_FORWARDED_FOR" => "198.51.100.9, 192.168.1.1") }

    assert_equal 429, get(plugin, "REMOTE_ADDR" => "192.168.1.1", "HTTP_X_FORWARDED_FOR" => "198.51.100.9").status
  end

  def test_uses_leftmost_forwarded_ip_when_every_hop_is_trusted
    plugin = build_plugin(trusted_proxies: ["10.0.0.0/8"])
    2.times { get(plugin, "REMOTE_ADDR" => "10.1.2.3", "HTTP_X_FORWARDED_FOR" => "10.0.0.5, 10.9.9.9") }

    assert_equal 429, get(plugin, "REMOTE_ADDR" => "10.1.2.3", "HTTP_X_FORWARDED_FOR" => "10.0.0.5").status
  end

  def test_copies_frozen_app_headers_before_adding_rate_headers
    frozen_app = ->(_env) { [200, { "content-type" => "text/plain" }.freeze, ["ok"]] }
    response = get(build_plugin, {}, frozen_app)

    assert_equal 200, response.status
    assert_rate_headers(response, limit: LIMIT, remaining: 1, reset: PERIOD)
  end

  def test_passes_max_keys_to_the_default_store
    plugin = build_plugin(max_keys: 2)
    2.times { get(plugin, "REMOTE_ADDR" => "203.0.113.1") }
    get(plugin, "REMOTE_ADDR" => "203.0.113.2")
    get(plugin, "REMOTE_ADDR" => "203.0.113.3")

    response = get(plugin, "REMOTE_ADDR" => "203.0.113.1")
    assert_equal 200, response.status
    assert_rate_headers(response, limit: LIMIT, remaining: 1, reset: PERIOD)
  end

  def test_max_keys_keeps_keys_that_were_not_evicted
    plugin = build_plugin(max_keys: 3)
    2.times { get(plugin, "REMOTE_ADDR" => "203.0.113.1") }
    get(plugin, "REMOTE_ADDR" => "203.0.113.2")
    get(plugin, "REMOTE_ADDR" => "203.0.113.3")

    assert_equal 429, get(plugin, "REMOTE_ADDR" => "203.0.113.1").status
  end

  def test_rejects_max_keys_together_with_a_custom_store
    store = Boto::Plugins::RateLimit::MemoryStore.new(clock: @clock)

    assert_raises(ArgumentError) { build_plugin(store: store, max_keys: 2) }
  end

  def test_store_unavailable_returns_its_error_response_without_calling_app
    store = FailingStore.new(Boto::Error::ServiceUnavailable.new("rate limit store unavailable"))
    app = ->(_env) { flunk "app must not be called when the store is unavailable" }

    response = get(build_plugin(store: store), {}, app)

    assert_equal 503, response.status
    assert_includes response.headers["content-type"], "problem+json"
    assert_equal "rate limit store unavailable", JSON.parse(response.body)["detail"]
    refute response.headers.key?("ratelimit-limit")
  end

  def test_store_error_that_is_not_a_boto_error_propagates
    store = FailingStore.new(RuntimeError.new("boom"))

    assert_raises(RuntimeError) { get(build_plugin(store: store)) }
  end

  def test_rejects_invalid_options
    assert_invalid(limit: 0)
    assert_invalid(limit: "2")
    assert_invalid(period: nil)
    assert_invalid(period: -60)
    assert_invalid(key: "not callable")
    assert_invalid(trusted_proxies: ["not-an-ip"])
    assert_invalid(trusted_proxies: "10.0.0.0/8")
    assert_invalid(max_keys: 0)
  end

  private

  def build_plugin(**options)
    Boto::Plugins::RateLimit.new(
      env_name: "production", limit: LIMIT, period: PERIOD, clock: @clock, **options
    )
  end

  def get(plugin, env = {}, app = OK_APP)
    Rack::MockRequest.new(->(rack_env) { plugin.call(rack_env, app) }).get("/", env)
  end

  def assert_rate_headers(response, limit:, remaining:, reset:)
    assert_equal limit.to_s, response.headers["ratelimit-limit"]
    assert_equal remaining.to_s, response.headers["ratelimit-remaining"]
    assert_equal reset.to_s, response.headers["ratelimit-reset"]
  end

  def assert_invalid(**options)
    assert_raises(ArgumentError) { build_plugin(**options) }
  end
end
