# frozen_string_literal: true

require "boto"
require_relative "../../support/database"

module BenchDbSchema
  DB = BenchDatabase.connect

  class UserSchema < Boto::Schema
    field :id, Integer
    field :name, String
  end

  class User < Boto::Endpoint
    get "/users/:id"
    param :id, Integer
    returns UserSchema

    def call(id:)
      row = DB[:users].where(id:).first
      not_found("user not found") unless row
      row
    end
  end
end

run Boto::App.new(namespace: BenchDbSchema, env_name: "production", error_output: $stderr)
