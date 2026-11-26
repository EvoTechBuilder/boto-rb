# frozen_string_literal: true

module Lkorders
  class Ping < Boto::Endpoint
    get "/ping"
    def call = { thing: Lkdomain::Thing.name }
  end
end
