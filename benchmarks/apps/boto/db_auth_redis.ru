# frozen_string_literal: true

require "boto"
require "boto/redis"
require_relative "../../support/database"

# Igual ao db_auth, mas o rate limit conta no Redis. Mede o custo do round trip ao Redis.
module BenchDbAuthRedis
  DB = BenchDatabase.connect
  TOKEN = "bench-token"
  RATE_LIMIT = 1_000_000_000
  RATE_PERIOD = 60
  REDIS_URL = ENV.fetch("REDIS_URL", "redis://127.0.0.1:6379/15")
  REDIS_PREFIX = "boto:bench"

  class User < Boto::Endpoint
    get "/users/:id"
    param :id, Integer

    def call(id:)
      row = DB[:users].where(id:).first
      not_found("user not found") unless row
      row
    end
  end

  STORE = Boto::Redis::RateLimitStore.new(url: REDIS_URL, prefix: REDIS_PREFIX)
  CONFIGURATION = Boto::Configuration.new(env_name: "production")
  CONFIGURATION.use(:auth, strategy: :bearer, tokens: [TOKEN])
  CONFIGURATION.use(:rate_limit, limit: RATE_LIMIT, period: RATE_PERIOD, store: STORE)
end

run Boto::App.new(namespace: BenchDbAuthRedis, plugins: BenchDbAuthRedis::CONFIGURATION.plugins,
                  env_name: "production", error_output: $stderr)
