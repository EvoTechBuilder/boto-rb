# frozen_string_literal: true

require "test_helper"
require "tmpdir"

module ConfigurationTestPlugins
  class Hosts < Boto::Plugin
    scope :global
  end

  class RateLimit < Boto::Plugin; end
  class CustomThing < Boto::Plugin; end
  class Other < Boto::Plugin; end

  class Allowing < Boto::Plugin
    attr_reader :allow

    private

    def configure(allow:)
      @allow = allow
    end
  end
end

module Boto
  module Plugins; end

  class ConfigurationTest < Minitest::Test
    CURRENT_KEY = Boto::Configuration::CURRENT_KEY

    def setup
      @config = Boto::Configuration.new(env_name: "test")
      Boto::Plugins.const_set(:TestEcho, Class.new(Boto::Plugin))
    end

    def teardown
      Boto::Plugins.send(:remove_const, :TestEcho)
      Thread.current[CURRENT_KEY] = nil
    end

    def test_stores_env_name
      assert_equal "test", @config.env_name
    end

    def test_use_accepts_plugin_class_and_options
      @config.use ConfigurationTestPlugins::Allowing, allow: %w[api.loja.com]
      plugin = @config.plugin(:allowing)

      assert_kind_of ConfigurationTestPlugins::Allowing, plugin
      assert_equal %w[api.loja.com], plugin.allow
      assert_equal "test", plugin.env_name
    end

    def test_use_returns_self
      assert_same @config, @config.use(ConfigurationTestPlugins::Hosts)
    end

    def test_use_resolves_symbol_name_under_boto_plugins
      @config.use :test_echo

      assert_kind_of Boto::Plugins::TestEcho, @config.plugin(:test_echo)
    end

    def test_use_resolves_string_name
      @config.use "test_echo"

      assert_kind_of Boto::Plugins::TestEcho, @config.plugin(:test_echo)
    end

    def test_invalid_name_is_rejected
      error = assert_raises(ArgumentError) { @config.use "Rate-Limit" }

      assert_match(/Rate-Limit/, error.message)
    end

    def test_unknown_name_points_to_security_gem
      error = assert_raises(ArgumentError) { @config.use :no_such_plugin }

      assert_equal %(unknown plugin :no_such_plugin (add gem "boto-rb-security" to the Gemfile)), error.message
    end

    def test_class_must_inherit_from_plugin
      error = assert_raises(ArgumentError) { @config.use String }

      assert_match(/Boto::Plugin/, error.message)
    end

    def test_other_argument_types_are_rejected
      assert_raises(ArgumentError) { @config.use 42 }
    end

    def test_duplicate_class_is_rejected
      @config.use ConfigurationTestPlugins::Hosts

      error = assert_raises(ArgumentError) { @config.use ConfigurationTestPlugins::Hosts }

      assert_equal "plugin :hosts already enabled", error.message
    end

    def test_duplicate_name_is_rejected
      @config.use :test_echo

      error = assert_raises(ArgumentError) { @config.use :test_echo }

      assert_equal "plugin :test_echo already enabled", error.message
    end

    def test_unknown_plugin_option_is_rejected
      assert_raises(ArgumentError) { @config.use ConfigurationTestPlugins::Allowing }
    end

    def test_plugins_are_sorted_by_order_then_declaration
      @config.use ConfigurationTestPlugins::CustomThing
      @config.use ConfigurationTestPlugins::RateLimit
      @config.use ConfigurationTestPlugins::Other
      @config.use ConfigurationTestPlugins::Hosts

      assert_equal %i[hosts rate_limit custom_thing other], names(@config.plugins)
    end

    def test_plugins_list_is_frozen
      @config.use ConfigurationTestPlugins::Hosts

      assert_predicate @config.plugins, :frozen?
    end

    def test_global_and_endpoint_plugins_split_by_scope
      @config.use ConfigurationTestPlugins::RateLimit
      @config.use ConfigurationTestPlugins::Hosts

      assert_equal %i[hosts], names(@config.global_plugins)
      assert_equal %i[rate_limit], names(@config.endpoint_plugins)
    end

    def test_plugin_finds_by_name
      @config.use ConfigurationTestPlugins::Hosts

      assert_kind_of ConfigurationTestPlugins::Hosts, @config.plugin(:hosts)
      assert_kind_of ConfigurationTestPlugins::Hosts, @config.plugin("hosts")
      assert_nil @config.plugin(:cors)
    end

    def test_load_of_missing_file_gives_empty_config
      config = Boto::Configuration.load("/no/such/dir/app.rb", env_name: "production")

      assert_empty config.plugins
      assert_equal "production", config.env_name
    end

    def test_load_evaluates_file_with_boto_configure
      Dir.mktmpdir do |dir|
        path = write_app(dir, <<~RUBY)
          Boto.configure do |app|
            app.use ConfigurationTestPlugins::Allowing, allow: %w[api.loja.com]
          end
        RUBY

        config = Boto::Configuration.load(path, env_name: "development")

        assert_equal %w[api.loja.com], config.plugin(:allowing).allow
        assert_equal "development", config.env_name
      end
    end

    def test_configure_outside_boot_raises
      error = assert_raises(Boto::Configuration::OutsideBootError) { Boto.configure { |_app| } }

      assert_equal "Boto.configure must run while a project boots (config/app.rb)", error.message
    end

    def test_load_restores_outer_configuration_after_success
      outer = Boto::Configuration.new(env_name: "outer")

      with_current(outer) do
        Dir.mktmpdir do |dir|
          Boto::Configuration.load(write_app(dir, "Boto.configure { |_app| }\n"), env_name: "test")
        end

        assert_same outer, Thread.current[CURRENT_KEY]
      end
    end

    def test_load_of_missing_file_keeps_outer_configuration
      outer = Boto::Configuration.new(env_name: "outer")

      with_current(outer) do
        Boto::Configuration.load("/no/such/dir/app.rb", env_name: "test")

        assert_same outer, Thread.current[CURRENT_KEY]
      end
    end

    def test_load_restores_outer_configuration_when_file_raises
      outer = Boto::Configuration.new(env_name: "outer")

      with_current(outer) do
        Dir.mktmpdir do |dir|
          path = write_app(dir, "raise ArgumentError, 'broken app.rb'\n")

          assert_raises(ArgumentError) { Boto::Configuration.load(path, env_name: "test") }
        end

        assert_same outer, Thread.current[CURRENT_KEY]
      end
    end

    private

    def names(plugins)
      plugins.map { |plugin| plugin.class.plugin_name }
    end

    def write_app(dir, source)
      path = File.join(dir, "app.rb")
      File.write(path, source)
      path
    end

    def with_current(config)
      previous = Thread.current[CURRENT_KEY]
      Thread.current[CURRENT_KEY] = config
      yield
    ensure
      Thread.current[CURRENT_KEY] = previous
    end
  end
end
