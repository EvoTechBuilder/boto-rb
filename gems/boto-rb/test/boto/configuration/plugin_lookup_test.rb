# frozen_string_literal: true

require "test_helper"

module Boto
  module Plugins; end

  class Configuration
    class PluginLookupTest < Minitest::Test
      class Hosts < Boto::Plugin; end

      def setup
        Boto::Plugins.const_set(:TestEcho, Class.new(Boto::Plugin))
      end

      def teardown
        Boto::Plugins.send(:remove_const, :TestEcho)
      end

      def test_class_is_returned_as_is
        assert_same Hosts, PluginLookup.resolve(Hosts)
      end

      def test_symbol_and_string_names_resolve_under_boto_plugins
        assert_same Boto::Plugins::TestEcho, PluginLookup.resolve(:test_echo)
        assert_same Boto::Plugins::TestEcho, PluginLookup.resolve("test_echo")
      end

      def test_invalid_name_is_rejected
        error = assert_raises(ArgumentError) { PluginLookup.resolve("Rate-Limit") }

        assert_match(/Rate-Limit/, error.message)
      end

      def test_unknown_name_points_to_gem_that_provides_it
        error = assert_raises(ArgumentError) { PluginLookup.resolve(:no_such_plugin) }

        assert_equal %(unknown plugin :no_such_plugin (add the gem that provides it to the Gemfile, e.g. "boto-rb-security")),
                     error.message
      end

      def test_inflections_override_camelized_name
        assert_equal "OpenAPI", Boto::INFLECTIONS.fetch("openapi")
        assert_equal "OpenAPI", PluginLookup.send(:camelize, "openapi")
        assert_equal "RateLimit", PluginLookup.send(:camelize, "rate_limit")
      end

      def test_class_must_inherit_from_plugin
        error = assert_raises(ArgumentError) { PluginLookup.resolve(String) }

        assert_match(/Boto::Plugin/, error.message)
      end

      def test_other_argument_types_are_rejected
        assert_raises(ArgumentError) { PluginLookup.resolve(42) }
      end
    end
  end
end
