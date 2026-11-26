# frozen_string_literal: true

require "sinatra/base"
require "json"
require_relative "../../support/database"

class BenchSinatraDb < Sinatra::Base
  set :environment, :production
  set :logging, false

  DB = BenchDatabase.connect

  get "/users/:id" do
    content_type :json
    row = DB[:users].where(id: params[:id].to_i).first
    halt 404, { error: "user not found" }.to_json unless row

    row.to_json
  end
end

run BenchSinatraDb
