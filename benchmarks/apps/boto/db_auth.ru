# frozen_string_literal: true

require "boto"
require_relative "../../support/database"

# db com os plugins :auth (bearer) e :rate_limit. O limite e alto de proposito: mede o custo, nao bloqueia.
module BenchDbAuth
  DB = BenchDatabase.connect
  TOKEN = "bench-token"
  RATE_LIMIT = 1_000_000_000
  RATE_PERIOD = 60

  class User < Boto::Endpoint
    get "/users/:id"
    param :id, Integer

    def call(id:)
      row = DB[:users].where(id:).first
      not_found("user not found") unless row
      row
    end
  end

  CONFIGURATION = Boto::Configuration.new(env_name: "production")
  CONFIGURATION.use(:auth, strategy: :bearer, tokens: [TOKEN])
  CONFIGURATION.use(:rate_limit, limit: RATE_LIMIT, period: RATE_PERIOD)
end

run Boto::App.new(namespace: BenchDbAuth, plugins: BenchDbAuth::CONFIGURATION.plugins,
                  env_name: "production", error_output: $stderr)
