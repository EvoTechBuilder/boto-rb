# frozen_string_literal: true

require "test_helper"
require "json"
require_relative "../../support/panel_fakes"

module Boto
  module Gateway
    class JsonViewTest < Minitest::Test
      SERVICE_KEYS = %w[name prefix port health routes openapi swagger env].freeze

      def test_top_level_shape
        data = parsed(PanelFakes.page)

        assert_equal %w[gateway env solution_env services], data.keys
        assert_equal "gateway", data["gateway"]
        assert_equal "development", data["env"]
      end

      def test_service_shape_and_health
        catalogo = service(PanelFakes.page, "catalogo")

        assert_equal SERVICE_KEYS, catalogo.keys
        assert_equal({ "status" => "ready", "detail" => nil }, catalogo["health"])
        assert_nil service(PanelFakes.page, "pedidos")["swagger"]
      end

      def test_routes_have_method_path_and_endpoint
        route = service(PanelFakes.page, "catalogo")["routes"].find { |r| r["method"] == "GET" }

        assert_equal %w[method path endpoint], route.keys
        assert_equal "GET", route["method"]
        assert_equal "/products", route["path"]
      end

      def test_links_keep_the_prefix_and_the_script_name
        catalogo = service(PanelFakes.page(base: "/gw"), "catalogo")

        assert_equal "/gw/catalogo/openapi.json", catalogo["openapi"]
      end

      def test_values_are_masked_and_secrets_are_not_in_the_body
        body = JSON.generate(parsed(PanelFakes.page))
        database = service(PanelFakes.page, "catalogo")["env"].find { |row| row["name"] == "DATABASE_URL" }

        assert_equal({ "name" => "DATABASE_URL", "value" => "postgres://catalogo:••••••••@localhost/catalogo_dev",
                       "source" => "apps/catalogo/.env.development", "masked" => true }, database)
        refute_includes JsonView.render(PanelFakes.page), "s3cret"
        refute_includes body, "k_live_123"
      end

      def test_failing_health_carries_the_detail
        services = { "catalogo" => PanelFakes.catalogo_app(checks: { "database" => -> { false } }) }
        health = service(PanelFakes.page(services: services), "catalogo")["health"]

        assert_equal "failing", health["status"]
        assert_includes health["detail"], "database"
      end

      private

      def parsed(page)
        JSON.parse(JsonView.render(page))
      end

      def service(page, name)
        parsed(page)["services"].find { |service| service["name"] == name }
      end
    end
  end
end
