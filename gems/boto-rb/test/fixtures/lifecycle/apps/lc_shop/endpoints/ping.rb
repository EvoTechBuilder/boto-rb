# frozen_string_literal: true

module LcShop
  class Ping < Boto::Endpoint
    get "/ping"
    def call = { pong: true }
  end
end
