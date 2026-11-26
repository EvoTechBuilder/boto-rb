# frozen_string_literal: true

require "json"

module Boto
  module Plugins
    # Answers the liveness probe (/health/live) and the readiness probe (/health/ready) before any other
    # plugin or routing, so the probes need no credentials and are not affected by :hosts or :auth.
    class Health < Boto::Plugin
      scope :global

      LIVE_PATH = "/health/live"
      READY_PATH = "/health/ready"
      PROBE_PATHS = [LIVE_PATH, READY_PATH].freeze
      GET = "GET"
      HEAD = "HEAD"
      PROBE_METHODS = [GET, HEAD].freeze
      STATUS_OK = "ok"
      STATUS_FAIL = "fail"
      HTTP_OK = 200
      HTTP_UNAVAILABLE = 503
      JSON_TYPE = "application/json"
      LIVE_BODY = '{"status":"ok"}'
      DRAINING_BODY = '{"status":"fail"}'
      DEFAULT_TIMEOUT = 1

      def attach(app)
        @app = app
      end

      # Plugin checks are collected here, once the app lists its plugins; the user's checks win on a name clash.
      def start
        @checks = plugin_checks.merge(@checks).freeze
      end

      def drain
        @draining = true
      end

      def call(env, app)
        return app.call(env) unless probe?(env)

        env["PATH_INFO"] == LIVE_PATH ? live_response : ready_response
      end

      private

      def configure(checks: {}, timeout: DEFAULT_TIMEOUT, error_output: $stderr)
        @checks = validate_checks(checks)
        @timeout = validate_timeout(timeout)
        @error_output = error_output
        @draining = false
      end

      def probe?(env)
        PROBE_PATHS.include?(env["PATH_INFO"]) && PROBE_METHODS.include?(env["REQUEST_METHOD"])
      end

      def live_response
        json_response(HTTP_OK, LIVE_BODY)
      end

      def ready_response
        return json_response(HTTP_UNAVAILABLE, DRAINING_BODY) if @draining

        checks = run_checks
        healthy = !checks.value?(STATUS_FAIL)
        json_response(healthy ? HTTP_OK : HTTP_UNAVAILABLE, ready_body(healthy, checks))
      end

      def ready_body(healthy, checks)
        JSON.generate(status: healthy ? STATUS_OK : STATUS_FAIL, checks: checks)
      end

      def json_response(status, body)
        [status, { "content-type" => JSON_TYPE }, [body]]
      end

      # All checks start at once; each one gets whatever time is left of the shared deadline.
      def run_checks
        deadline = now + @timeout
        threads = @checks.map { |name, check| [name, Thread.new { check_status(name, check) }] }
        threads.to_h { |name, thread| [name, join_status(name, thread, deadline)] }
      end

      def join_status(name, thread, deadline)
        return thread.value if thread.join([deadline - now, 0].max)

        log("health check #{name} timed out after #{@timeout}s")
        STATUS_FAIL
      end

      def check_status(name, check)
        check.call ? STATUS_OK : STATUS_FAIL
      rescue StandardError => e
        log("health check #{name} raised #{e.class}: #{e.message}")
        STATUS_FAIL
      end

      def plugin_checks
        @app.plugins.each_with_object({}) do |plugin, all|
          plugin.health_checks.each { |name, check| all[name.to_s] = check }
        end
      end

      def log(message)
        @error_output.puts("health: #{message}")
      end

      def now
        Process.clock_gettime(Process::CLOCK_MONOTONIC)
      end

      def validate_checks(checks)
        raise ArgumentError, "health: checks must be a Hash of name => callable" unless checks.is_a?(Hash)

        checks.to_h { |name, check| validate_check(name, check) }.freeze
      end

      def validate_check(name, check)
        raise ArgumentError, "health: check name must be a Symbol or String, got #{name.inspect}" unless named?(name)
        raise ArgumentError, "health: check #{name} must respond to call" unless check.respond_to?(:call)

        [name.to_s, check]
      end

      def named?(name)
        name.is_a?(Symbol) || name.is_a?(String)
      end

      def validate_timeout(timeout)
        return timeout if timeout.is_a?(Numeric) && timeout.positive?

        raise ArgumentError, "health: timeout must be a positive number, got #{timeout.inspect}"
      end
    end
  end
end
