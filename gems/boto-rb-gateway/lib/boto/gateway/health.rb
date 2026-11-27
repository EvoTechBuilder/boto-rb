# frozen_string_literal: true

require "rack/mock_request"

module Boto
  module Gateway
    # Runs a service's own readiness probe in this process, so the panel shows what /health/ready says.
    module Health
      Result = Data.define(:status, :detail)

      PROBE_PATH = "/health/ready"
      HEALTH_PLUGIN = :health
      OK = 200
      DETAIL_LIMIT = 200
      READY = :ready
      FAILING = :failing
      NONE = :none

      module_function

      def check(app, host: nil)
        return Result.new(status: NONE, detail: nil) unless app.plugins.any? { |plugin| health_plugin?(plugin) }

        probe(app, host)
      rescue StandardError => error
        failing("#{error.class}: #{error.message}")
      end

      def probe(app, host)
        env = Rack::MockRequest.env_for(PROBE_PATH)
        env["HTTP_HOST"] = host if host
        status, _headers, body = app.call(env)
        return Result.new(status: READY, detail: nil) if status == OK

        failing(read_body(body))
      end

      def health_plugin?(plugin)
        plugin.class.plugin_name == HEALTH_PLUGIN
      end

      def failing(detail)
        Result.new(status: FAILING, detail: detail)
      end

      def read_body(body)
        text = +""
        body.each { |chunk| text << chunk }
        text[0, DETAIL_LIMIT]
      ensure
        body.close if body.respond_to?(:close)
      end
    end
  end
end
