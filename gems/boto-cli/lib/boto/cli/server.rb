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

      # rack_middleware replaces the deprecated Falcon::Server.middleware.
      def falcon_server(app, port)
        endpoint = Async::HTTP::Endpoint.parse("http://#{host}:#{port}")
        Falcon::Server.new(Falcon::Server.rack_middleware(app), endpoint)
      end
    end
  end
end
