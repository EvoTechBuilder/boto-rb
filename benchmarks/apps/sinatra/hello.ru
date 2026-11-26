# frozen_string_literal: true

require "sinatra/base"
require "json"

class BenchSinatraHello < Sinatra::Base
  set :environment, :production
  set :logging, false

  get "/" do
    content_type :json
    { hello: "world" }.to_json
  end
end

run BenchSinatraHello
