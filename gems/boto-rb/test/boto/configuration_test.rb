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

  class Pooled < Boto::Plugin
    attr_reader :url, :pool

    private

    def configure(url:, pool: 1)
      @url = url
      @pool = pool
    end
  end

  # Records each instance in the log array passed as option, so tests can count builds.
  class Counting < Boto::Plugin
    private

    def configure(log:)
      log << self
    end
  end

  # Calls the option value, so tests can check whether a lambda ran.
  class Resolving < Boto::Plugin
    attr_reader :value

    private

    def configure(value:)
      @value = value.call
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
      Boto::Plugins.send(:remove_const, :LookupProbe) if Boto::Plugins.const_defined?(:LookupProbe, false)
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

    def test_use_finds_plugin_file_on_load_path
      with_feature("lookup_probe", <<~RUBY) do
        module Boto::Plugins
          class LookupProbe < Boto::Plugin; end
        end
      RUBY
        @config.use :lookup_probe

        assert_kind_of Boto::Plugins::LookupProbe, @config.plugin(:lookup_probe)
      end
    end

    def test_load_error_from_plugin_dependency_propagates
      with_feature("lookup_broken", %(require "missing_dependency_xyz"\n)) do
        error = assert_raises(LoadError) { @config.use :lookup_broken }

        assert_equal "missing_dependency_xyz", error.path
      end
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
      @config.use ConfigurationTestPlugins::Allowing

      assert_raises(ArgumentError) { @config.plugins }
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

    def test_use_in_later_phase_merges_options_and_environment_wins
      with_phase(:app) { @config.use ConfigurationTestPlugins::Pooled, url: "general", pool: 10 }
      with_phase(:environment) { @config.use ConfigurationTestPlugins::Pooled, url: "development" }

      plugin = @config.plugin(:pooled)

      assert_equal "development", plugin.url
      assert_equal 10, plugin.pool
    end

    def test_use_in_later_phase_adds_new_plugin
      with_phase(:environment) { @config.use ConfigurationTestPlugins::Hosts }

      assert_kind_of ConfigurationTestPlugins::Hosts, @config.plugin(:hosts)
    end

    def test_duplicate_use_in_environment_phase_after_merge_is_rejected
      with_phase(:app) { @config.use ConfigurationTestPlugins::Pooled, url: "general" }
      with_phase(:environment) { @config.use ConfigurationTestPlugins::Pooled, url: "development" }

      error = assert_raises(ArgumentError) do
        with_phase(:environment) { @config.use ConfigurationTestPlugins::Pooled, url: "again" }
      end

      assert_equal "plugin :pooled already enabled", error.message
    end

    def test_duplicate_use_in_environment_phase_is_rejected
      error = assert_raises(ArgumentError) do
        with_phase(:environment) do
          @config.use ConfigurationTestPlugins::Hosts
          @config.use ConfigurationTestPlugins::Hosts
        end
      end

      assert_equal "plugin :hosts already enabled", error.message
    end

    def test_remove_drops_declared_plugin
      @config.use ConfigurationTestPlugins::Hosts

      assert_same @config, @config.remove(:hosts)
      assert_nil @config.plugin(:hosts)
    end

    def test_remove_of_undeclared_plugin_is_rejected
      error = assert_raises(ArgumentError) { @config.remove(:no_such_plugin) }

      assert_equal "plugin :no_such_plugin is not enabled", error.message
    end

    def test_remove_then_use_in_later_phase_starts_fresh
      @config.use ConfigurationTestPlugins::Pooled, url: "general", pool: 10
      with_phase(:environment) do
        @config.remove(:pooled)
        @config.use ConfigurationTestPlugins::Pooled, url: "development"
      end

      plugin = @config.plugin(:pooled)

      assert_equal "development", plugin.url
      assert_equal 1, plugin.pool
    end

    def test_plugin_is_built_once_with_merged_options
      log = []
      @config.use ConfigurationTestPlugins::Counting, log: log
      @config.plugins
      @config.plugin(:counting)
      @config.plugins

      assert_equal 1, log.size
    end

    def test_overridden_option_lambda_is_not_called
      with_phase(:app) { @config.use ConfigurationTestPlugins::Resolving, value: -> { raise "general lambda ran" } }
      with_phase(:environment) { @config.use ConfigurationTestPlugins::Resolving, value: -> { "development" } }

      assert_equal "development", @config.plugin(:resolving).value
    end

    def test_fixed_order_is_kept_after_merge
      @config.use ConfigurationTestPlugins::CustomThing
      @config.use ConfigurationTestPlugins::RateLimit
      @config.use ConfigurationTestPlugins::Other
      with_phase(:environment) do
        @config.use ConfigurationTestPlugins::Hosts
        @config.use ConfigurationTestPlugins::RateLimit
      end

      assert_equal %i[hosts rate_limit custom_thing other], names(@config.plugins)
    end

    def test_use_after_build_is_rejected
      @config.use ConfigurationTestPlugins::Hosts
      @config.plugins

      error = assert_raises(ArgumentError) { @config.use ConfigurationTestPlugins::Other }

      assert_equal "configuration is already built", error.message
    end

    def test_remove_after_build_is_rejected
      @config.use ConfigurationTestPlugins::Hosts
      @config.plugins

      error = assert_raises(ArgumentError) { @config.remove(:hosts) }

      assert_equal "configuration is already built", error.message
    end

    def test_env_is_the_object_given_to_configuration
      env = Object.new
      config = Boto::Configuration.new(env_name: "test", env: env)

      assert_same env, config.env
    end

    def test_env_is_nil_when_not_given
      assert_nil @config.env
    end

    def test_load_gives_config_files_access_to_env
      Dir.mktmpdir do |dir|
        path = write_app(dir, <<~RUBY)
          Boto.configure do |app|
            app.use ConfigurationTestPlugins::Allowing, allow: [app.env.fetch("ALLOWED")]
          end
        RUBY

        config = Boto::Configuration.load(path, env_name: "test", env: { "ALLOWED" => "api.loja.com" })

        assert_equal %w[api.loja.com], config.plugin(:allowing).allow
      end
    end

    def test_load_evaluates_app_then_environment_file
      Dir.mktmpdir do |dir|
        app = write_app(dir, <<~RUBY)
          Boto.configure do |app|
            app.use ConfigurationTestPlugins::Pooled, url: "general", pool: 4
            app.use ConfigurationTestPlugins::Allowing, allow: %w[api.loja.com]
          end
        RUBY
        environment = write_file(dir, "development.rb", <<~RUBY)
          Boto.configure do |app|
            app.use ConfigurationTestPlugins::Pooled, url: "development"
          end
        RUBY

        config = Boto::Configuration.load([app, environment], env_name: "development")

        assert_equal "development", config.plugin(:pooled).url
        assert_equal 4, config.plugin(:pooled).pool
        assert_equal %w[api.loja.com], config.plugin(:allowing).allow
      end
    end

    def test_load_skips_missing_environment_file
      Dir.mktmpdir do |dir|
        app = write_app(dir, "Boto.configure { |app| app.use ConfigurationTestPlugins::Hosts }\n")
        missing = File.join(dir, "environments", "production.rb")

        config = Boto::Configuration.load([app, missing], env_name: "production")

        assert_kind_of ConfigurationTestPlugins::Hosts, config.plugin(:hosts)
      end
    end

    def test_load_rejects_more_than_two_files
      error = assert_raises(ArgumentError) do
        Boto::Configuration.load(%w[a.rb b.rb c.rb], env_name: "test")
      end

      assert_equal "expected at most 2 config files", error.message
    end

    private

    def names(plugins)
      plugins.map { |plugin| plugin.class.plugin_name }
    end

    def with_phase(name, &block)
      @config.with_phase(name, &block)
    end

    def write_app(dir, source)
      write_file(dir, "app.rb", source)
    end

    def write_file(dir, name, source)
      path = File.join(dir, name)
      File.write(path, source)
      path
    end

    # Puts boto/<feature>.rb on $LOAD_PATH for the block; undoes the load path and feature cache after.
    def with_feature(feature, source)
      Dir.mktmpdir do |dir|
        Dir.mkdir(File.join(dir, "boto"))
        File.write(File.join(dir, "boto", "#{feature}.rb"), source)
        $LOAD_PATH.unshift(dir)
        begin
          yield
        ensure
          $LOAD_PATH.delete(dir)
          $LOADED_FEATURES.reject! { |loaded| loaded.end_with?("/boto/#{feature}.rb") }
        end
      end
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
