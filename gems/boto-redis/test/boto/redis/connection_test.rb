# frozen_string_literal: true

require "test_helper"

class Boto::Redis::ConnectionTest < Minitest::Test
  def test_set_and_get_round_trip
    client = ::RedisClient.new(url: redis_url_or_skip)
    key = "boto-redis:test:#{Process.pid}"

    client.call("SET", key, "value", "EX", 60)
    assert_equal "value", client.call("GET", key)
    client.call("DEL", key)
  ensure
    client&.close
  end
end
