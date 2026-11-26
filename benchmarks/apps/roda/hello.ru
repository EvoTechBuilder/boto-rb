# frozen_string_literal: true

require "roda"

class BenchRodaHello < Roda
  plugin :json

  route do |r|
    r.root { { hello: "world" } }
  end
end

run BenchRodaHello
