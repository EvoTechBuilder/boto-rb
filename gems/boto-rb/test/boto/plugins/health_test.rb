# frozen_string_literal: true

require "test_helper"
require "rack/mock"
require "stringio"
require "json"

# Stand-ins: the core must not depend on boto-rb-security, so :hosts and a plugin with checks are faked here.
module HealthFakes
  class Hosts < Boto::Plugin
    scope :global

    def call(_env, _app)
      Boto::Error::Forbidden.new("blocked").to_response
    end
  end

  class Checked < Boto::Plugin
    def health_checks = { cache: -> { true } }
  end

  module Shop
    class Show < Boto::Endpoint
      get "/users/:id"
      param :id, Integer
      def call(id:) = { id: }
    end
  end
end

module Boto
  module Plugins
    class HealthTest < Minitest::Test
      def setup
        @error_output = StringIO.new
      end

      def health(checks: {}, timeout: 1)
        Boto::Plugins::Health.new(env_name: "production", checks: checks, timeout: timeout, error_output: @error_output)
      end

      def app(plugins: [health], namespace: HealthFakes::Shop, env_name: "production")
        Boto::App.new(namespace: namespace, plugins: plugins, env_name: env_name, error_output: @error_output).tap(&:start)
      end

      def get(application, path)
        Rack::MockRequest.new(application).get(path)
      end

      def json(body)
        JSON.parse(body)
      end

      def test_live_is_ok_even_when_a_check_fails
        res = get(app(plugins: [health(checks: { db: -> { false } })]), "/health/live")
        assert_equal 200, res.status
        assert_equal({ "status" => "ok" }, json(res.body))
      end

      def test_ready_is_ok_when_all_checks_pass
        application = app(plugins: [health(checks: { db: -> { true }, redis: -> { :yes } })])
        res = get(application, "/health/ready")
        assert_equal 200, res.status
        assert_equal({ "status" => "ok", "checks" => { "db" => "ok", "redis" => "ok" } }, json(res.body))
      end

      def test_ready_is_unavailable_when_a_check_returns_false
        res = get(app(plugins: [health(checks: { db: -> { false } })]), "/health/ready")
        assert_equal 503, res.status
        assert_equal({ "status" => "fail", "checks" => { "db" => "fail" } }, json(res.body))
      end

      def test_ready_is_unavailable_when_a_check_raises_and_keeps_the_message_out_of_the_body
        application = app(plugins: [health(checks: { db: -> { raise "password=secret" } })])
        res = get(application, "/health/ready")
        assert_equal 503, res.status
        refute_includes res.body, "secret"
        assert_includes @error_output.string, "db raised RuntimeError: password=secret"
      end

      def test_ready_is_unavailable_when_a_check_times_out
        application = app(plugins: [health(timeout: 0.05, checks: { slow: -> { sleep 0.5 } })])
        res = get(application, "/health/ready")
        assert_equal 503, res.status
        assert_equal({ "status" => "fail", "checks" => { "slow" => "fail" } }, json(res.body))
        assert_includes @error_output.string, "health check slow timed out after 0.05s"
      end

      def test_ready_is_unavailable_while_draining_and_live_stays_ok
        application = app
        application.drain!
        assert_equal 503, get(application, "/health/ready").status
        assert_equal 200, get(application, "/health/live").status
      end

      def test_checks_of_other_plugins_join_the_user_checks
        application = app(plugins: [health(checks: { db: -> { true } }), HealthFakes::Checked.new(env_name: "production")])
        res = get(application, "/health/ready")
        assert_equal 200, res.status
        assert_equal({ "db" => "ok", "cache" => "ok" }, json(res.body)["checks"])
      end

      def test_user_check_wins_over_a_plugin_check_with_the_same_name
        application = app(plugins: [health(checks: { cache: -> { false } }), HealthFakes::Checked.new(env_name: "production")])
        assert_equal 503, get(application, "/health/ready").status
      end

      def test_probes_answer_before_a_global_plugin_that_would_block
        application = app(plugins: [health, HealthFakes::Hosts.new(env_name: "production")])
        assert_equal 200, get(application, "/health/live").status
        assert_equal 200, get(application, "/health/ready").status
        assert_equal 403, get(application, "/users/7").status
      end

      def test_other_paths_pass_through_to_the_app
        application = app
        assert_equal 200, get(application, "/users/7").status
        assert_equal 404, get(application, "/health").status
        assert_equal 404, get(application, "/health/live/extra").status
      end

      def test_post_to_ready_passes_through_without_running_checks
        ran = false
        application = app(plugins: [health(checks: { db: -> { ran = true } })])
        assert_equal 404, Rack::MockRequest.new(application).post("/health/ready").status
        refute ran
      end

      def test_head_request_has_no_body
        res = Rack::MockRequest.new(app).head("/health/live")
        assert_equal 200, res.status
        assert_empty res.body
      end

      def test_non_callable_check_fails_at_boot
        error = assert_raises(ArgumentError) do
          Boto::Configuration.new(env_name: "production").use(:health, checks: { db: "not callable" })
        end
        assert_includes error.message, "db must respond to call"
      end

      def test_non_positive_timeout_fails_at_boot
        error = assert_raises(ArgumentError) do
          Boto::Configuration.new(env_name: "production").use(:health, timeout: 0)
        end
        assert_includes error.message, "timeout must be a positive number"
      end

      def test_checks_must_be_a_hash_with_named_checks
        assert_raises(ArgumentError) { health(checks: [[:db, -> { true }]]) }
        assert_raises(ArgumentError) { health(checks: { 1 => -> { true } }) }
      end

      def test_drain_is_idempotent
        application = app
        application.drain!
        application.drain!
        assert_equal 503, get(application, "/health/ready").status
      end

      def test_openapi_does_not_list_health_paths
        application = app(env_name: "development")
        body = get(application, "/openapi.json").body
        refute_includes body, "/health"
        assert_includes body, "/users/{id}"
      end
    end
  end
end
