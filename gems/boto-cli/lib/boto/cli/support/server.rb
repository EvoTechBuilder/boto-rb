# frozen_string_literal: true

require "async"
require "async/http/endpoint"
require "falcon/server"

module Boto
  module CLI
    # Serves one Rack app per port, all of them inside a single Async reactor.
    class Server
      DEFAULT_HOST = "127.0.0.1"

      attr_reader :apps_by_port, :host

      def initialize(apps_by_port, host: DEFAULT_HOST)
        @apps_by_port = apps_by_port
        @host = host
      end

      def run
        Async do |task|
          apps_by_port.each { |port, app| task.async { falcon_server(app, port).run } }
        end
      end

      private

      # Falcon's HTTP cache is on by default and would replay GET responses without reaching the app,
      # skipping auth, rate limits and per-user data; an API server must not cache, so it is disabled.
      def falcon_server(app, port)
        endpoint = Async::HTTP::Endpoint.parse("http://#{host}:#{port}")
        Falcon::Server.new(Falcon::Server.rack_middleware(app, cache: false), endpoint)
      end
    end
  end
end
