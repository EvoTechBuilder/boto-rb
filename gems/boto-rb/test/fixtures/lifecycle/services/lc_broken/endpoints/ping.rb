# frozen_string_literal: true

module LcBroken
  class Ping < Boto::Endpoint
    get "/ping"
    def call = { pong: true }
  end
end
