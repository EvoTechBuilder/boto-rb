# frozen_string_literal: true

require "boto"

module BenchHello
  class Root < Boto::Endpoint
    get "/"
    def call = { hello: "world" }
  end
end

run Boto::App.new(namespace: BenchHello, env_name: "production", error_output: $stderr)
