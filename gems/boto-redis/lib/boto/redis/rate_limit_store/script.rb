# frozen_string_literal: true

require "digest"

module Boto
  module Redis
    class RateLimitStore
      # INCR and, on the first hit of a window, PEXPIRE, in one atomic round trip.
      # Returns [count, pttl]: the counter and the milliseconds left before it expires.
      module Script
        SOURCE = <<~LUA.freeze
          local count = redis.call('INCR', KEYS[1])
          if count == 1 then redis.call('PEXPIRE', KEYS[1], ARGV[1]) end
          return {count, redis.call('PTTL', KEYS[1])}
        LUA
        SHA1 = Digest::SHA1.hexdigest(SOURCE).freeze

        # Runs by SHA1 and loads the source when Redis has not cached it yet (restart, SCRIPT FLUSH).
        def self.run(client, key, ttl_ms)
          client.call("EVALSHA", SHA1, 1, key, ttl_ms)
        rescue ::RedisClient::NoScriptError
          client.call("EVAL", SOURCE, 1, key, ttl_ms)
        end
      end
    end
  end
end
