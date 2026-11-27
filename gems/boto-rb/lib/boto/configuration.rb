# frozen_string_literal: true

module Boto
  # Plugins declared by config/app.rb and config/environments/<env>.rb. Declarations are kept until
  # the first read of #plugins, which builds every plugin once with its final options.
  class Configuration
    class OutsideBootError < StandardError; end

    # Kept as data (not an instance) so a later file can merge options into it.
    Declaration = Struct.new(:klass, :options, :phase, keyword_init: true)

    CURRENT_KEY = :boto_configuration
    OUTSIDE_BOOT_MESSAGE = "Boto.configure must run while a project boots (config/app.rb)"
    APP_PHASE = :app
    ENVIRONMENT_PHASE = :environment
    PHASES = [APP_PHASE, ENVIRONMENT_PHASE].freeze
    BUILT_MESSAGE = "configuration is already built"

    attr_reader :env_name, :env

    # paths is one file or [config/app.rb, config/environments/<env>.rb]; missing files are skipped.
    def self.load(paths, env_name:, env: nil)
      paths = Array(paths)
      raise ArgumentError, "expected at most #{PHASES.size} config files" if paths.size > PHASES.size

      config = new(env_name: env_name, env: env)
      paths.zip(PHASES).each do |path, phase|
        next unless File.file?(path)

        config.with_phase(phase) { evaluate(path, config) }
      end
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

    # env is the Boto::Env of the project; nil until the loader passes one.
    def initialize(env_name:, env: nil)
      @env_name = env_name
      @env = env
      @declarations = {}
      @phase = APP_PHASE
    end

    def use(plugin_ref, **options)
      ensure_not_built!
      declare(PluginLookup.resolve(plugin_ref), options)
      self
    end

    def remove(name)
      ensure_not_built!
      removed = @declarations.delete(name.to_sym)
      raise ArgumentError, "plugin :#{name} is not enabled" unless removed

      self
    end

    # Runs the block as if its declarations came from the given file phase.
    def with_phase(name)
      previous = @phase
      @phase = name
      yield
    ensure
      @phase = previous
    end

    def plugins
      @plugins ||= build_plugins
    end

    def global_plugins
      plugins_in(:global)
    end

    def endpoint_plugins
      plugins_in(:endpoint)
    end

    def plugin(name)
      plugins.find { |instance| instance.class.plugin_name == name.to_sym }
    end

    # Builds only the named plugin, or nil when it is not declared. Tools such as boto db read one plugin without
    # building the others, whose secrets (API tokens, for instance) the task does not need.
    def build_only(name)
      declaration = @declarations[name.to_sym]
      declaration && build(declaration)
    end

    private

    # Re-declaring in a later phase merges options (the later file wins per key); in the same phase it is a mistake.
    def declare(klass, options)
      name = klass.plugin_name
      existing = @declarations[name]
      raise ArgumentError, "plugin :#{name} already enabled" if existing&.phase == @phase

      merged = existing ? existing.options.merge(options) : options
      @declarations[name] = Declaration.new(klass: klass, options: merged, phase: @phase)
    end

    def build_plugins
      instances = @declarations.values.map { |declaration| build(declaration) }
      instances.sort_by.with_index { |plugin, index| [plugin.class.order_index, index] }.freeze
    end

    def build(declaration)
      declaration.klass.new(env_name: env_name, **declaration.options)
    end

    def ensure_not_built!
      raise ArgumentError, BUILT_MESSAGE if @plugins
    end

    def plugins_in(scope)
      plugins.select { |plugin| plugin.class.scope == scope }.freeze
    end
  end
end
