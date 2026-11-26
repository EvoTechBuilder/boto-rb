# frozen_string_literal: true

require "boto"
require_relative "../../support/database"

module BenchDb
  DB = BenchDatabase.connect

  class User < Boto::Endpoint
    get "/users/:id"
    param :id, Integer

    def call(id:)
      row = DB[:users].where(id:).first
      not_found("user not found") unless row
      row
    end
  end
end

run Boto::App.new(namespace: BenchDb, env_name: "production", error_output: $stderr)
