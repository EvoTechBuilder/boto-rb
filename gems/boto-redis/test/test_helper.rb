# frozen_string_literal: true

require "minitest/autorun"
require "uri"
require "boto/redis"

module RedisTestHelper
  DEFAULT_REDIS_URL = "redis://127.0.0.1:6379/15"

  # Uses the database 15 by default so tests do not touch real data.
  def redis_url_or_skip
    url = ENV.fetch("REDIS_URL", DEFAULT_REDIS_URL)
    return url if redis_reachable?(url)

    skip "Redis not available at #{redis_endpoint(url)}; set REDIS_URL to run"
  end

  private

  def redis_reachable?(url)
    ::RedisClient.new(url: url, connect_timeout: 0.2).call("PING") == "PONG"
  rescue ::RedisClient::Error
    false
  end

  def redis_endpoint(url)
    uri = URI(url)
    "#{uri.host}:#{uri.port}"
  end
end

Minitest::Test.include(RedisTestHelper)
