# frozen_string_literal: true

require "test_helper"
require_relative "../../support/panel_fakes"

module Boto
  module Gateway
    class HealthTest < Minitest::Test
      # Answers the probe with whatever it is given; stands in for an app whose probe misbehaves.
      FakeApp = Struct.new(:plugins, :response) do
        def call(_env) = response
      end

      RaisingApp = Struct.new(:plugins) do
        def call(_env) = raise(IOError, "database is down")
      end

      def test_app_with_a_passing_probe_is_ready
        assert_equal [:ready, nil], status_of(PanelFakes.catalogo_app)
      end

      def test_app_without_health_plugin_has_no_check
        assert_equal [:none, nil], status_of(PanelFakes.pedidos_app)
      end

      def test_failing_probe_carries_its_body_as_detail
        result = Health.check(PanelFakes.catalogo_app(checks: { "database" => -> { false } }))

        assert_equal :failing, result.status
        assert_includes result.detail, "database"
      end

      def test_probe_carries_the_panel_host
        seen = nil
        app = FakeApp.new([health_plugin], [200, {}, []])
        app.define_singleton_method(:call) { |env| (seen = env["HTTP_HOST"]) && response }
        Health.check(app, host: "localhost:3000")

        assert_equal "localhost:3000", seen
      end

      def test_failing_probe_detail_is_cut_to_the_limit
        app = FakeApp.new([health_plugin], [503, {}, ["x" * 500]])
        result = Health.check(app)

        assert_equal Health::DETAIL_LIMIT, result.detail.size
      end

      def test_exception_becomes_a_failing_status_with_class_and_message
        result = Health.check(RaisingApp.new([health_plugin]))

        assert_equal Health::Result.new(status: :failing, detail: "IOError: database is down"), result
      end

      private

      def health_plugin = PanelFakes.health

      def status_of(app)
        result = Health.check(app)
        [result.status, result.detail]
      end
    end
  end
end
