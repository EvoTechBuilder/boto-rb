# frozen_string_literal: true

require "test_helper"

module PluginTestPlugins
  class Hosts < Boto::Plugin; end
  class RateLimit < Boto::Plugin; end
  class CustomThing < Boto::Plugin; end
  class HTTPCache < Boto::Plugin; end

  class Tagger < Boto::Plugin
    scope :global

    def call(env, app)
      env[:tag] = @tag
      app.call(env)
    end

    private

    def configure(tag:)
      @tag = tag
    end
  end
end

module Boto
  class PluginTest < Minitest::Test
    def test_default_scope_is_endpoint
      assert_equal :endpoint, PluginTestPlugins::Hosts.scope
    end

    def test_declared_scope_is_read_back
      assert_equal :global, PluginTestPlugins::Tagger.scope
    end

    def test_scope_rejects_unknown_value
      error = assert_raises(ArgumentError) { Class.new(Boto::Plugin) { scope :nowhere } }

      assert_match(/nowhere/, error.message)
    end

    def test_plugin_name_is_snake_case_of_last_segment
      assert_equal :rate_limit, PluginTestPlugins::RateLimit.plugin_name
      assert_equal :custom_thing, PluginTestPlugins::CustomThing.plugin_name
    end

    def test_plugin_name_handles_acronyms
      assert_equal :http_cache, PluginTestPlugins::HTTPCache.plugin_name
    end

    def test_order_index_follows_known_order
      assert_equal Boto::Plugin::ORDER.index(:hosts), PluginTestPlugins::Hosts.order_index
      assert_equal Boto::Plugin::ORDER.index(:rate_limit), PluginTestPlugins::RateLimit.order_index
    end

    def test_order_index_puts_third_party_plugins_last
      assert_equal Boto::Plugin::ORDER.size, PluginTestPlugins::CustomThing.order_index
    end

    def test_env_name_is_kept
      assert_equal "production", PluginTestPlugins::Hosts.new(env_name: "production").env_name
    end

    def test_development_predicate
      assert_predicate PluginTestPlugins::Hosts.new(env_name: "development"), :development?
      refute_predicate PluginTestPlugins::Hosts.new(env_name: "production"), :development?
    end

    def test_base_plugin_rejects_any_option
      assert_raises(ArgumentError) { PluginTestPlugins::Hosts.new(env_name: "test", allow: []) }
    end

    def test_subclass_receives_options_in_configure
      tagger = PluginTestPlugins::Tagger.new(env_name: "test", tag: "x")
      env = {}
      tagger.call(env, ->(inner_env) { inner_env })

      assert_equal "x", env[:tag]
    end

    def test_subclass_requires_its_options
      assert_raises(ArgumentError) { PluginTestPlugins::Tagger.new(env_name: "test") }
    end

    def test_base_call_is_not_implemented
      assert_raises(NotImplementedError) { PluginTestPlugins::Hosts.new(env_name: "test").call({}, nil) }
    end
  end
end
