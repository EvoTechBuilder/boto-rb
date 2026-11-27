# frozen_string_literal: true

module Boto
  # Plugins declared by one config/app.rb. Filled while Configuration.load evaluates the file.
  class Configuration
    class OutsideBootError < StandardError; end

    PLUGIN_NAME = /\A[a-z][a-z0-9_]*\z/
    SECURITY_GEM = "boto/security"
    CURRENT_KEY = :boto_configuration
    OUTSIDE_BOOT_MESSAGE = "Boto.configure must run while a project boots (config/app.rb)"

    attr_reader :env_name

    def self.load(path, env_name:)
      config = new(env_name: env_name)
      evaluate(path, config) if File.file?(path)
      config
    end

    def self.capture
      Thread.current[CURRENT_KEY] || raise(OutsideBootError, OUTSIDE_BOOT_MESSAGE)
    end

    # The thread-local is set only while the file runs, so nested loads restore the outer one.
    def self.evaluate(path, config)
      previous = Thread.current[CURRENT_KEY]
      Thread.current[CURRENT_KEY] = config
      Kernel.load(path)
    ensure
      Thread.current[CURRENT_KEY] = previous
    end
    private_class_method :evaluate

    def initialize(env_name:)
      @env_name = env_name
      @plugins = []
    end

    def use(plugin_ref, **options)
      klass = resolve(plugin_ref)
      raise ArgumentError, "plugin :#{klass.plugin_name} already enabled" if plugin(klass.plugin_name)

      @plugins << klass.new(env_name: env_name, **options)
      self
    end

    def plugins
      @plugins.sort_by.with_index { |plugin, index| [plugin.class.order_index, index] }.freeze
    end

    def global_plugins
      plugins_in(:global)
    end

    def endpoint_plugins
      plugins_in(:endpoint)
    end

    def plugin(name)
      @plugins.find { |instance| instance.class.plugin_name == name.to_sym }
    end

    private

    def plugins_in(scope)
      plugins.select { |plugin| plugin.class.scope == scope }.freeze
    end

    def resolve(plugin_ref)
      case plugin_ref
      when Class then check_class(plugin_ref)
      when Symbol, String then lookup(plugin_ref.to_s)
      else raise ArgumentError, "plugin must be a name or a Boto::Plugin class, got #{plugin_ref.inspect}"
      end
    end

    def check_class(klass)
      raise ArgumentError, "#{klass} must inherit from Boto::Plugin" unless klass < Plugin

      klass
    end

    def lookup(name)
      raise ArgumentError, "invalid plugin name #{name.inspect}" unless name.match?(PLUGIN_NAME)

      klass = find_plugin(name) ||
              require_and_find(SECURITY_GEM, name) ||
              require_and_find("boto/#{name}", name)
      raise ArgumentError, unknown_plugin_message(name) unless klass

      check_class(klass)
    end

    def unknown_plugin_message(name)
      %(unknown plugin :#{name} (add the gem that provides it to the Gemfile, e.g. "boto-rb-security"))
    end

    def find_plugin(name)
      return unless defined?(Boto::Plugins)

      constant = camelize(name)
      Boto::Plugins.const_get(constant, false) if Boto::Plugins.const_defined?(constant, false)
    end

    # Only a missing feature itself is "not found"; a LoadError from a dependency of that feature propagates.
    def require_and_find(feature, name)
      require feature
      find_plugin(name)
    rescue LoadError => error
      raise unless error.path == feature

      nil
    end

    def camelize(name)
      Boto::INFLECTIONS.fetch(name) { name.split("_").map(&:capitalize).join }
    end
  end
end
