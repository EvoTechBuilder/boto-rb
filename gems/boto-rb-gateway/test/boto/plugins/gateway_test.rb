# frozen_string_literal: true

require "test_helper"
require "rack/mock"

# An endpoint of the gateway's own, to show that unclaimed paths reach the gateway.
module GatewayPluginFakes
  module Gate
    class Own < Boto::Endpoint
      get "/own"
      def call = { own: true }
    end
  end
end

module Boto
  module Plugins
    class GatewayTest < Minitest::Test
      FakeApp = Struct.new(:services)
      GATEWAY = ->(env) { [200, {}, ["gateway #{env["PATH_INFO"]}"]] }

      def setup
        @services = { "catalogo" => echo("catalogo") }
      end

      def test_default_prefix_routes_to_the_service
        assert_equal "catalogo|/catalogo|/products/1", call_path("/catalogo/products/1")
      end

      def test_prefix_override_replaces_the_default
        gateway = attached(prefixes: { "catalogo" => "/loja" })

        assert_equal "catalogo|/loja|/products", call_path("/loja/products", gateway)
        assert_equal "gateway /catalogo/products", call_path("/catalogo/products", gateway)
      end

      def test_service_receives_script_name_and_path_info_without_the_prefix
        assert_equal "catalogo|/catalogo|/products/1", call_path("/catalogo/products/1")
      end

      def test_prefix_alone_reaches_the_service_with_an_empty_path_info
        assert_equal "catalogo|/catalogo|", call_path("/catalogo")
      end

      def test_segment_boundary_keeps_similar_paths_on_the_gateway
        assert_equal "gateway /catalogox", call_path("/catalogox")
      end

      def test_path_without_prefix_goes_to_the_gateway
        assert_equal "gateway /own", call_path("/own")
      end

      def test_restores_the_env_after_the_call
        env = Rack::MockRequest.env_for("/catalogo/products/1")
        before = env.dup

        attached.call(env, GATEWAY)

        assert_equal before, env
      end

      def test_production_refuses_to_attach
        error = assert_raises(ArgumentError) { attached(env_name: "production") }

        assert_equal "gateway runs in development and test only for now; in production, route with your ingress",
                     error.message
      end

      def test_panel_defaults_to_development_only
        assert plugin(env_name: "development").panel?
        refute plugin(env_name: "test").panel?
      end

      def test_explicit_panel_option_wins
        refute plugin(env_name: "development", panel: false).panel?
        assert plugin(env_name: "test", panel: true).panel?
      end

      def test_rejects_prefixes_that_are_not_a_hash
        error = assert_raises(ArgumentError) { plugin(prefixes: "catalogo") }

        assert_match(/\Agateway: prefixes must be a Hash/, error.message)
      end

      def test_rejects_panel_that_is_not_a_boolean
        error = assert_raises(ArgumentError) { plugin(panel: "yes") }

        assert_equal "gateway: panel must be true, false or nil, got \"yes\"", error.message
      end

      def test_invalid_prefix_fails_at_attach
        error = assert_raises(ArgumentError) { attached(prefixes: { "catalogo" => "/" }) }

        assert_match(/\Agateway: prefix of "catalogo" cannot be "\/"/, error.message)
      end

      def test_app_with_gateway_plugin_routes_services_and_its_own_endpoints
        app = Boto::App.new(namespace: GatewayPluginFakes::Gate, plugins: [plugin], env_name: "test",
                            services: @services)
        app.start
        request = Rack::MockRequest.new(app)

        assert_equal "catalogo|/catalogo|/products/1", request.get("/catalogo/products/1").body
        assert_equal 200, request.get("/own").status
      end

      private

      def echo(name)
        ->(env) { [200, {}, ["#{name}|#{env["SCRIPT_NAME"]}|#{env["PATH_INFO"]}"]] }
      end

      def plugin(env_name: "test", **options)
        Boto::Plugins::Gateway.new(env_name: env_name, **options)
      end

      def attached(env_name: "test", **options)
        plugin(env_name: env_name, **options).tap { |gateway| gateway.attach(FakeApp.new(@services)) }
      end

      def call_path(path, gateway = attached)
        response = gateway.call(Rack::MockRequest.env_for(path), GATEWAY)
        response[2].first
      end
    end
  end
end
