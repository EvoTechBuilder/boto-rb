# frozen_string_literal: true

require "roda"
require_relative "../../support/database"

class BenchRodaDb < Roda
  plugin :json

  DB = BenchDatabase.connect

  route do |r|
    r.get "users", Integer do |id|
      row = DB[:users].where(id:).first
      next row if row

      response.status = 404
      { error: "user not found" }
    end
  end
end

run BenchRodaDb
