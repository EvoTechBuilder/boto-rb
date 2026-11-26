# frozen_string_literal: true

require "test_helper"
require "digest"
require "securerandom"

class Boto::Redis::RateLimitStore::ScriptTest < Minitest::Test
  Script = Boto::Redis::RateLimitStore::Script

  def test_sha1_is_the_digest_of_the_source
    assert_equal Digest::SHA1.hexdigest(Script::SOURCE), Script::SHA1
    assert_predicate Script::SOURCE, :frozen?
  end

  def test_run_loads_the_script_when_redis_has_not_cached_it
    redis = ::RedisClient.new(url: redis_url_or_skip)
    key = "boto:test:script:#{SecureRandom.hex(4)}"
    redis.call("SCRIPT", "FLUSH")

    assert_equal 1, Script.run(redis, key, 60_000).first
    assert_equal [1], redis.call("SCRIPT", "EXISTS", Script::SHA1)
    assert_equal 2, Script.run(redis, key, 60_000).first
  ensure
    redis&.call("DEL", key)
    redis&.close
  end
end
