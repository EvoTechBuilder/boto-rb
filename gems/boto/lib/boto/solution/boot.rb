# frozen_string_literal: true

require "set"

module Boto
  # Loads a solution's projects in dependency order and builds the Rack app of one project.
  class Boot
    CONFIG_FILE = File.join("config", "app.rb")
    SKIP_ENV = "BOTO_SKIP_ISOLATION"
    SKIP_VALUE = "1"
    SKIP_WARNING = "Boto: project isolation check skipped (BOTO_SKIP_ISOLATION=1)"

    def initialize(solution, root:, env: ENV, warn_output: $stderr)
      @solution = solution
      @root = root
      @env = env
      @warn_output = warn_output
      @loaders = {}
      @checked = Set.new
      @skip_warned = false
    end

    def checked_projects
      @checked.dup.freeze
    end

    def load(name)
      verify_isolation(name)
      loaders = load_order(name).map { |item| loader_for(item) }
      loaders.each(&:setup)
      loaders.each(&:eager_load)
      loader_for(name).namespace
    end

    def app(name, **app_options)
      env_name = app_options.fetch(:env_name) { ENV.fetch("BOTO_ENV", "production") }
      namespace = load(name)
      config = Configuration.load(config_path(name), env_name: env_name)
      App.new(**app_options, env_name: env_name, namespace: namespace, plugins: config.plugins)
    end

    def shutdown
      @loaders.each_value(&:unload)
      @loaders.clear
    end

    private

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
