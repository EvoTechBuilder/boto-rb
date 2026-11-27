# frozen_string_literal: true

require "rack/urlmap"

module Boto
  module Plugins
    # Mounts the referenced HTTP services under their prefixes in this process, so one port serves the solution.
    # Runs before routing: a path no prefix claims falls through to the gateway's own endpoints.
    class Gateway < Boto::Plugin
      scope :global

      PRODUCTION = "production"
      NOT_IN_PRODUCTION = "gateway runs in development and test only for now; in production, route with your ingress"
      CASCADE_HEADER = "x-cascade"
      CASCADE_PASS = "pass"
      BOOLEANS = [true, false].freeze

      attr_reader :app, :mounts

      def attach(app)
        raise ArgumentError, NOT_IN_PRODUCTION if env_name == PRODUCTION

        @app = app
        @mounts = Boto::Gateway::Mounts.new(services: app.services, prefixes: @prefixes)
        @router = Rack::URLMap.new(@mounts.apps_by_prefix)
      end

      # Panel defaults to development only; an explicit true or false wins.
      def panel?
        @panel.nil? ? development? : @panel
      end

      def call(env, app)
        response = @router.call(env)
        return response unless cascade?(response)

        app.call(env)
      end

      private

      def configure(prefixes: {}, panel: nil)
        @prefixes = validate_prefixes(prefixes)
        @panel = validate_panel(panel)
      end

      def validate_prefixes(prefixes)
        return prefixes if prefixes.is_a?(Hash)

        raise ArgumentError, "gateway: prefixes must be a Hash of service name to prefix, got #{prefixes.inspect}"
      end

      def validate_panel(panel)
        return panel if panel.nil? || BOOLEANS.include?(panel)

        raise ArgumentError, "gateway: panel must be true, false or nil, got #{panel.inspect}"
      end

      # URLMap answers 404 with x-cascade: pass when no prefix matches; that is the only case that goes to the gateway.
      def cascade?(response)
        response[1][CASCADE_HEADER] == CASCADE_PASS
      end
    end
  end
end
