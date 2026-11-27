# frozen_string_literal: true

require "set"

module Boto
  # Loads a solution's projects in dependency order and builds the Rack app of one project.
  class Boot
    class InvalidEnvironmentError < ArgumentError; end

    CONFIG_FILE = File.join("config", "app.rb")
    ENVIRONMENTS_DIR = File.join("config", "environments")
    ENV_NAME_KEY = "BOTO_ENV"
    DEFAULT_ENV_NAME = "production"
    # Keeps BOTO_ENV safe to use in a file path (no "../").
    ENV_NAME_PATTERN = /\A[a-z][a-z0-9_]*\z/
    INVALID_ENV_NAME_MESSAGE = "invalid environment name %<name>s: use lowercase letters, digits and _"
    SKIP_ENV = "BOTO_SKIP_ISOLATION"
    SKIP_VALUE = "1"
    SKIP_WARNING = "Boto: project isolation check skipped (BOTO_SKIP_ISOLATION=1)"
    UNLOAD_WARNING = "Boto: failed to unload project %<name>s (%<error>s): %<message>s"

    # process_env: the variables set before any .env was read. A process that boots again (the dev reload) passes
    # the snapshot it took first, so solution values a previous boot wrote to ENV do not count as process values.
    def initialize(solution, root:, env: ENV, process_env: nil, warn_output: $stderr)
      @solution = solution
      @root = root
      @env = env
      @process_env = process_env&.to_h&.dup&.freeze
      @warn_output = warn_output
      @loaders = {}
      @apps = []
      @checked = Set.new
      @skip_warned = false
    end

    def checked_projects
      @checked.dup.freeze
    end

    # The block runs after the autoloads are set up and before the eager load (see #app).
    def load(name, &before_eager_load)
      Layout.check!(@solution, root: @root)
      verify_isolation(name)
      created = load_order(name).reject { @loaders.key?(_1) }
      load_loaders(load_order(name).map { loader_for(_1) }, created, &before_eager_load)
      loader_for(name).namespace
    end

    def app(name, **app_options)
      env_name = environment_name(app_options)
      config = nil
      # The configuration is read before the eager load: app.use :database requires boto-rb-data, whose
      # Boto::Repository the project's repositories inherit from. Constants named in config files still autoload.
      namespace = load(name) { config = configuration(name, env_name: env_name) }
      context = ProjectContext.new(name: name, env_name: env_name, env: config.env)
      namespace.extend(ProjectApp::Namespace).bind_app(context)
      app = App.new(**app_options, env_name: env_name, namespace: namespace, plugins: config.plugins)
      app.start
      @apps << app
      app
    end

    # Builds the project's Configuration without loading its code or starting its plugins, so the CLI can
    # read plugin options (e.g. a database URL) before the tables exist.
    def configuration(name, env_name:)
      env_name = validate_environment_name(env_name)
      env = project_env(name, env_name)
      Configuration.load(config_paths(name, env_name), env_name: env_name, env: env)
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
      yield if block_given?
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

    def environment_name(app_options)
      validate_environment_name(app_options.fetch(:env_name) { @env.fetch(ENV_NAME_KEY, DEFAULT_ENV_NAME) })
    end

    def validate_environment_name(env_name)
      return env_name if env_name.is_a?(String) && ENV_NAME_PATTERN.match?(env_name)

      raise InvalidEnvironmentError, format(INVALID_ENV_NAME_MESSAGE, name: env_name.inspect)
    end

    def project_dir(name)
      File.join(@root, @solution.project(name).path)
    end

    def config_paths(name, env_name)
      dir = project_dir(name)
      [File.join(dir, CONFIG_FILE), File.join(dir, ENVIRONMENTS_DIR, "#{env_name}.rb")]
    end

    # Precedence is process > project > solution, so the process snapshot is taken before solution values reach ENV.
    def project_env(name, env_name)
      load_solution_env(env_name)
      project_layer = Env::Files.read(project_dir(name), env_name: env_name)
      Env.new(@process_env, project_layer, @solution_env)
    end

    # Solution values reach @env (ENV by default) for gems that read it directly, without overwriting it.
    def load_solution_env(env_name)
      return if @solution_env

      @process_env ||= @env.to_h.dup.freeze
      @solution_env = Env::Files.read(@root, env_name: env_name)
      @solution_env.each { |key, value| @env[key] = value unless @env.key?(key) }
    end
  end
end
