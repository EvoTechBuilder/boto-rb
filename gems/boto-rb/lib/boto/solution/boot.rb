# frozen_string_literal: true

require "set"

module Boto
  # Loads a solution's projects in dependency order and builds the Rack app of one project.
  class Boot
    CONFIG_FILE = File.join("config", "app.rb")
    SKIP_ENV = "BOTO_SKIP_ISOLATION"
    SKIP_VALUE = "1"
    SKIP_WARNING = "Boto: project isolation check skipped (BOTO_SKIP_ISOLATION=1)"
    UNLOAD_WARNING = "Boto: failed to unload project %<name>s (%<error>s): %<message>s"

    def initialize(solution, root:, env: ENV, warn_output: $stderr)
      @solution = solution
      @root = root
      @env = env
      @warn_output = warn_output
      @loaders = {}
      @apps = []
      @checked = Set.new
      @skip_warned = false
    end

    def checked_projects
      @checked.dup.freeze
    end

    def load(name)
      verify_isolation(name)
      created = load_order(name).reject { @loaders.key?(_1) }
      load_loaders(load_order(name).map { loader_for(_1) }, created)
      loader_for(name).namespace
    end

    def app(name, **app_options)
      env_name = app_options.fetch(:env_name) { ENV.fetch("BOTO_ENV", "production") }
      namespace = load(name)
      config = Configuration.load(config_path(name), env_name: env_name)
      app = App.new(**app_options, env_name: env_name, namespace: namespace, plugins: config.plugins)
      app.start
      @apps << app
      app
    end

    # Stops the apps before unloading, so plugins still see the project code. Safe to call twice.
    def shutdown
      @apps.reverse_each(&:stop)
      @apps.clear
      unload_all
    end

    private

    def load_loaders(loaders, created)
      loaders.each(&:setup)
      loaders.each(&:eager_load)
    rescue StandardError
      discard(created)
      raise
    end

    def discard(names)
      names.each { |name| unload_quietly(name, @loaders.delete(name)) }
    end

    def unload_all
      @loaders.each { |name, loader| unload_quietly(name, loader) }
    ensure
      @loaders.clear
    end

    def unload_quietly(name, loader)
      loader.unload
    rescue StandardError => e
      @warn_output.puts(format(UNLOAD_WARNING, name: name, error: e.class, message: e.message))
    end

    def verify_isolation(name)
      pending = load_order(name).reject { @checked.include?(_1) }
      return if pending.empty?
      return warn_skipped if skip_isolation?

      violations = Isolation.check(@solution, root: @root, projects: pending)
      raise IsolationError.new(violations) unless violations.empty?

      @checked.merge(pending)
    end

    def skip_isolation?
      @env[SKIP_ENV] == SKIP_VALUE
    end

    def warn_skipped
      return if @skip_warned

      @skip_warned = true
      @warn_output.puts(SKIP_WARNING)
    end

    def load_order(name)
      @solution.dependencies_of(name) + [name]
    end

    def loader_for(name)
      @loaders[name] ||= ProjectLoader.new(@solution.project(name), root: @root)
    end

    def config_path(name)
      File.join(@root, @solution.project(name).path, CONFIG_FILE)
    end
  end
end
