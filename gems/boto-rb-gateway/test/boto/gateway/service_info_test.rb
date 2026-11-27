# frozen_string_literal: true

require "test_helper"
require_relative "../../support/panel_fakes"

module Boto
  module Gateway
    class ServiceInfoTest < Minitest::Test
      def test_build_reads_name_prefix_port_and_routes
        info = ServiceInfo.build("catalogo", "/catalogo", PanelFakes.catalogo_app, [])

        assert_equal ["catalogo", "/catalogo", 4101], [info.name, info.prefix, info.port]
        routes = info.routes.map { |route| [route.verb, route.path, route.endpoint] }

        assert_equal [["GET", "/products", "PanelFakes::Catalogo::ListProducts"],
                      ["POST", "/products", "PanelFakes::Catalogo::CreateProduct"]].sort,
                     routes.sort
      end

      def test_fixed_port_when_port_comes_from_a_file
        assert_equal false, ServiceInfo.build("catalogo", "/catalogo", PanelFakes.catalogo_app, []).random_port
      end

      def test_random_port_when_boto_run_sets_port
        app = PanelFakes.pedidos_app(port: 61_042)

        assert ServiceInfo.build("pedidos", "/pedidos", app, []).random_port
      end

      def test_health_status_drives_ready_and_failing_predicates
        ready = ServiceInfo.build("catalogo", "/catalogo", PanelFakes.catalogo_app, [])
        failing = ServiceInfo.build("catalogo", "/catalogo", PanelFakes.catalogo_app(checks: { "db" => -> { false } }), [])

        assert ready.ready?
        refute ready.failing?
        assert failing.failing?
      end

      def test_openapi_link_has_the_prefix_and_default_path
        info = ServiceInfo.build("catalogo", "/loja", PanelFakes.catalogo_app, [])

        assert_equal "/loja/openapi.json", info.openapi
      end

      def test_swagger_link_only_when_the_plugin_is_on
        app = Boto::App.new(namespace: PanelFakes::Catalogo, plugins: [PanelFakes::SwaggerUi.new(env_name: "development")],
                            env_name: "development")

        assert_nil ServiceInfo.build("catalogo", "/catalogo", PanelFakes.catalogo_app, []).swagger
        assert_equal "/catalogo/docs", ServiceInfo.build("catalogo", "/catalogo", app, []).swagger
      end

      def test_env_lists_the_project_variables_without_solution_keys
        info = ServiceInfo.build("catalogo", "/catalogo", PanelFakes.catalogo_app, ["REDIS_URL"])

        assert_equal %w[PORT DATABASE_URL NOTE], info.env.map(&:name)
      end
    end
  end
end
