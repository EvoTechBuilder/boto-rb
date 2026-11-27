# frozen_string_literal: true

require "test_helper"
require_relative "../../support/panel_fakes"

module Boto
  module Gateway
    class HtmlViewTest < Minitest::Test
      def test_shows_gateway_environment_host_and_summary
        html = render(PanelFakes.page)

        assert_includes html, "gateway PanelFakes::Gateway"
        assert_includes html, "development"
        assert_includes html, "localhost:3000"
        assert_includes html, "Health checked in-process at page load"
      end

      def test_service_head_has_name_prefix_port_and_fixed_port_note
        html = render(PanelFakes.page)

        assert_includes html, "<h2 class=\"service__name\">catalogo</h2>"
        assert_includes html, "<code class=\"prefix\">/catalogo</code>"
        assert_includes html, "href=\"http://localhost:4101\">localhost:4101</a>"
        assert_includes html, "fixed PORT"
      end

      def test_routes_show_verb_class_and_path_with_prefix
        html = render(PanelFakes.page)

        assert_includes html, "<span class=\"verb verb--get\">GET</span>"
        assert_includes html, "<span class=\"verb verb--post\">POST</span>"
        assert_includes html, "<span class=\"prefix-dim\">/catalogo</span>/products"
        assert_includes html, "PanelFakes::Catalogo::ListProducts"
      end

      def test_ready_and_no_health_check_labels
        html = render(PanelFakes.page)

        assert_includes html, "Ready"
        assert_includes html, "No health check"
      end

      def test_links_to_openapi_have_the_prefix
        html = render(PanelFakes.page)

        assert_includes html, "href=\"/catalogo/openapi.json\""
        assert_includes html, "href=\"/pedidos/openapi.json\""
      end

      def test_panel_and_service_links_follow_script_name
        html = render(PanelFakes.page(base: "/gw"))

        assert_includes html, "href=\"/gw/_boto/panel.css\""
        assert_includes html, "href=\"/gw/_boto/services.json\""
        assert_includes html, "href=\"/gw/catalogo/openapi.json\""
      end

      def test_variables_are_masked_and_secret_values_never_appear
        html = render(PanelFakes.page)

        assert_includes html, "postgres://catalogo:••••••••@localhost/catalogo_dev"
        assert_includes html, "SENTRY_DSN"
        refute_includes html, "s3cret"
        refute_includes html, "sentry.example"
      end

      def test_value_with_markup_is_escaped
        html = render(PanelFakes.page)

        assert_includes html, "&lt;script&gt;alert(1)&lt;/script&gt;"
        refute_match(/<script/i, html)
      end

      def test_page_has_no_inline_styles_or_scripts
        html = render(PanelFakes.page)

        refute_match(/style=/, html)
        refute_match(/<script/i, html)
      end

      def test_failing_health_shows_not_ready_and_the_reason
        services = { "catalogo" => PanelFakes.catalogo_app(checks: { "database" => -> { false } }) }
        html = render(PanelFakes.page(services: services))

        assert_includes html, "Not ready"
        assert_includes html, "health-detail"
        assert_includes html, "database"
      end

      def test_only_the_first_environment_is_open
        html = render(PanelFakes.page)

        assert_equal 1, html.scan(/<details class="service__env" open>/).size
        assert_equal 1, html.scan(/<details class="service__env">/).size
      end

      private

      def render(page)
        HtmlView.new(HtmlView.template).render(page)
      end
    end
  end
end
