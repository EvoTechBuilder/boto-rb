# frozen_string_literal: true

require "test_helper"

module Boto
  module Gateway
    class MountsTest < Minitest::Test
      CATALOGO = ->(_env) { [200, {}, []] }
      PEDIDOS = ->(_env) { [200, {}, []] }
      SERVICES = { "catalogo" => CATALOGO, "pedidos" => PEDIDOS }.freeze

      def test_default_prefix_is_the_service_name
        mounts = Mounts.new(services: SERVICES)

        assert_equal [["catalogo", "/catalogo", CATALOGO], ["pedidos", "/pedidos", PEDIDOS]], mounts.entries
      end

      def test_prefix_override_replaces_the_default_for_that_service_only
        mounts = Mounts.new(services: SERVICES, prefixes: { "catalogo" => "/loja" })

        assert_equal({ "/loja" => CATALOGO, "/pedidos" => PEDIDOS }, mounts.apps_by_prefix)
      end

      def test_no_services_mounts_nothing
        assert_equal({}, Mounts.new(services: {}).apps_by_prefix)
      end

      def test_prefix_must_be_a_string
        assert_invalid(prefixes: { "catalogo" => :loja }, message: "prefix of \"catalogo\" must be a String, got :loja")
      end

      def test_prefix_must_start_with_slash
        assert_invalid(prefixes: { "catalogo" => "loja" }, message: "must start with \"/\", got \"loja\"")
      end

      def test_prefix_cannot_be_root
        assert_invalid(prefixes: { "catalogo" => "/" }, message: "cannot be \"/\", got \"/\"")
      end

      def test_prefix_cannot_end_with_slash
        assert_invalid(prefixes: { "catalogo" => "/loja/" }, message: "cannot end with \"/\", got \"/loja/\"")
      end

      def test_prefix_cannot_use_the_panel_namespace
        assert_invalid(prefixes: { "catalogo" => "/_boto/loja" }, message: "reserved for the panel")
      end

      def test_default_prefix_cannot_use_the_panel_namespace
        assert_invalid(services: { "_boto" => CATALOGO }, message: "prefix of \"_boto\" cannot start with \"/_boto\"")
      end

      def test_prefixes_cannot_repeat_between_services
        assert_invalid(prefixes: { "pedidos" => "/catalogo" },
                       message: "prefix \"/catalogo\" of \"pedidos\" is used by another service")
      end

      def test_prefixes_must_name_a_ref
        assert_invalid(prefixes: { "estoque" => "/estoque" }, message: "prefixes names \"estoque\", which is not a ref")
      end

      private

      def assert_invalid(message:, services: SERVICES, prefixes: {})
        error = assert_raises(ArgumentError) { Mounts.new(services: services, prefixes: prefixes) }

        assert_includes error.message, message
        assert error.message.start_with?("gateway: ")
      end

      def test_prefixes_accept_symbol_keys
        mounts = Mounts.new(services: SERVICES, prefixes: { catalogo: "/loja" })

        assert_equal "/loja", mounts.entries.first[1]
      end
    end
  end
end
