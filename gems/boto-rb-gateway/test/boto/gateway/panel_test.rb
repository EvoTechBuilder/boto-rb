# frozen_string_literal: true

require "test_helper"
require "json"
require "rack/mock"
require_relative "../../support/panel_fakes"

module Boto
  module Gateway
    class PanelTest < Minitest::Test
      def test_html_page_is_served_with_no_store
        response = mock.get("/_boto")

        assert_equal 200, response.status
        assert_equal "text/html; charset=utf-8", response.headers["content-type"]
        assert_equal "no-store", response.headers["cache-control"]
        assert_includes response.body, "Boto"
      end

      def test_json_has_the_same_services
        data = JSON.parse(mock.get("/_boto/services.json").body)

        assert_equal %w[catalogo pedidos], data["services"].map { |service| service["name"] }
      end

      def test_stylesheet_is_served_as_css
        response = mock.get("/_boto/panel.css")

        assert_equal 200, response.status
        assert_equal "text/css; charset=utf-8", response.headers["content-type"]
        assert_includes response.body, ".topbar"
      end

      def test_unknown_path_under_panel_is_not_found
        assert_equal 404, mock.get("/_boto/x").status
      end

      def test_post_is_not_allowed_with_allow_header
        response = mock.post("/_boto")

        assert_equal 405, response.status
        assert_equal "GET, HEAD", response.headers["allow"]
      end

      def test_head_is_answered_without_a_body
        response = mock.head("/_boto")

        assert_equal 200, response.status
        assert_empty response.body
      end

      def test_script_name_reaches_the_links
        response = mock.get("/_boto", "SCRIPT_NAME" => "/gw")

        assert_includes response.body, "href=\"/gw/_boto/services.json\""
      end

      def test_panel_is_on_by_default_in_development
        assert_equal 200, mock.get("/_boto").status
      end

      def test_panel_false_leaves_the_path_to_the_gateway
        plugin = Boto::Plugins::Gateway.new(env_name: "development", panel: false)

        assert_equal 404, mock(plugin: plugin).get("/_boto").status
      end

      def test_panel_is_off_outside_development
        plugin = Boto::Plugins::Gateway.new(env_name: "test")

        assert_equal 404, mock(plugin: plugin).get("/_boto").status
      end

      private

      def mock(plugin: Boto::Plugins::Gateway.new(env_name: "development"))
        services = { "catalogo" => PanelFakes.catalogo_app, "pedidos" => PanelFakes.pedidos_app }
        Rack::MockRequest.new(PanelFakes.gateway_app(services: services, plugins: [plugin]))
      end
    end
  end
end
