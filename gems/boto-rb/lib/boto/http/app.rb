# frozen_string_literal: true

require "json"
require "rack/utils"

module Boto
  # Rack app for one project. Discovers the endpoints under a namespace at boot and
  # dispatches each request through a router compiled once.
  class App
    class BootError < StandardError; end

    Entry = Data.define(
      :endpoint, :status, :needs_input, :needs_query, :body_schema, :return_schema, :returns_list, :handler
    )

    JSON_HEADERS_TYPE = "application/json"
    NO_CONTENT = 204
    INTERNAL_ERROR = 500
    EMPTY = {}.freeze
    NO_INPUT = [EMPTY, EMPTY].freeze
    HEAD = "HEAD"
    ROOT_PATH = "/"
    DEVELOPMENT = "development"
    BODY_PARAM = "body"
    GET = "GET"
    OPENAPI_PATH = "/openapi.json"
    OPENAPI_VERSION = "development"
    PATH_PARAMS_KEY = "boto.path_params"
    GLOBAL_SCOPE = :global
    AUTH_PLUGIN = :auth
    OPENAPI_PLUGIN = :openapi

    attr_reader :endpoints, :title

    def initialize(namespace:, plugins: [], env_name: ENV.fetch("BOTO_ENV", "production"), error_output: $stderr)
      @env_name = env_name
      @error_output = error_output
      @title = namespace.name.freeze
      @global_plugins, @endpoint_plugins = ordered(plugins).partition { |plugin| plugin.class.scope == GLOBAL_SCOPE }
      @auth_by_endpoint = {}
      @plugins_by_endpoint = {}
      @router = Router.new
      @endpoints = discover(namespace).each { |endpoint| register(endpoint) }.freeze
      @router.compile
      @handler = Boto::Plugin::Stack.build(@global_plugins, method(:dispatch))
      @openapi_json = build_openapi_json
    end

    def call(env)
      response = handle(env)
      env["REQUEST_METHOD"] == HEAD ? [response[0], response[1], []] : response
    end

    # The instance of :auth that guards the endpoint, or nil when the endpoint is not authenticated.
    def auth_for(endpoint)
      @auth_by_endpoint[endpoint]
    end

    # The global plugins plus the endpoint plugins that run on the endpoint (not skipped, including its own :auth).
    def plugins_for(endpoint)
      @global_plugins + @plugins_by_endpoint.fetch(endpoint, [])
    end

    # Every plugin the app runs at boot and shutdown: the declared ones plus the :auth instances of endpoints.
    def plugins
      declared = ordered(@global_plugins + @endpoint_plugins)
      declared + extra_auth_plugins(declared)
    end

    # Idempotent. A plugin that fails to start stops the ones already started, then the boot fails.
    def start
      return if @started_plugins

      @started_plugins = []
      lifecycle = plugins
      lifecycle.each { |plugin| plugin.attach(self) }
      lifecycle.each { |plugin| start_plugin(plugin) }
    end

    # Idempotent. Tells every plugin the app is draining (shutdown in progress); requests are not touched.
    def drain!
      return if @draining

      @draining = true
      plugins.each(&:drain)
    end

    # Idempotent. Stops the started plugins in reverse order; a failing stop is logged, not raised.
    def stop
      return unless @started_plugins

      @started_plugins.reverse_each { |plugin| stop_plugin(plugin) }
      @started_plugins = nil
    end

    private

    def start_plugin(plugin)
      plugin.start
      @started_plugins << plugin
    rescue StandardError => e
      stop
      raise BootError, "plugin :#{plugin.class.plugin_name} failed to start: #{e.class}: #{e.message}"
    end

    def stop_plugin(plugin)
      plugin.stop
    rescue StandardError => e
      log_error(e)
    end

    # The :auth instances built by `authenticate` are not in the plugin lists, so they are started here.
    def extra_auth_plugins(declared)
      @auth_by_endpoint.values.compact.uniq(&:object_id).reject do |auth|
        declared.any? { |plugin| plugin.equal?(auth) }
      end
    end

    def handle(env)
      @handler.call(env)
    rescue Boto::Error => e
      e.to_response
    rescue StandardError => e
      internal_error_response(e)
    end

    def discover(namespace)
      found = []
      collect(namespace, "#{namespace.name}::", Set[namespace], found)
      found.sort_by(&:name)
    end

    def collect(mod, prefix, visited, found)
      mod.constants(false).each do |const_name|
        value = mod.const_get(const_name, false)
        next unless inside_namespace?(value, prefix) && visited.add?(value)

        found << value if endpoint?(value)
        collect(value, prefix, visited, found)
      end
    end

    def inside_namespace?(value, prefix)
      value.is_a?(Module) && value.name&.start_with?(prefix)
    end

    def endpoint?(value)
      value < Boto::Endpoint && !value.route.nil?
    end

    def register(endpoint)
      check_path_params!(endpoint)
      endpoint.compile!
      check_skips!(endpoint)
      plugins = endpoint_plugins_for(endpoint)
      @plugins_by_endpoint[endpoint] = plugins
      @auth_by_endpoint[endpoint] = plugins.find { |plugin| plugin.class.plugin_name == AUTH_PLUGIN }
      @router.add(*endpoint.route, entry_for(endpoint, plugins))
    rescue Router::DuplicateRouteError, ArgumentError => e
      raise BootError, "#{endpoint.name}: #{e.message}"
    end

    def check_path_params!(endpoint)
      missing = endpoint.path_param_names - endpoint.params.names
      return if missing.empty?

      raise BootError, "#{endpoint.name}: path param :#{missing.first} is not declared"
    end

    def check_skips!(endpoint)
      endpoint.skipped_plugins.each { |name| check_skip!(endpoint, name) }
    end

    def check_skip!(endpoint, name)
      raise BootError, "#{endpoint.name}: cannot skip global plugin :#{name}" if plugin_named?(@global_plugins, name)
      return if plugin_named?(@endpoint_plugins, name)

      raise BootError, "#{endpoint.name}: skip :#{name} but plugin :#{name} is not enabled"
    end

    def plugin_named?(plugins, name)
      plugins.any? { |plugin| plugin.class.plugin_name == name }
    end

    def endpoint_plugins_for(endpoint)
      plugins = @endpoint_plugins.reject { |plugin| endpoint.skipped_plugins.include?(plugin.class.plugin_name) }
      return plugins unless endpoint.authentication

      kept = plugins.reject { |plugin| plugin.class.plugin_name == AUTH_PLUGIN }
      ordered(kept << endpoint_auth(endpoint))
    end

    def endpoint_auth(endpoint)
      strategy, options = endpoint.authentication
      Configuration.new(env_name: @env_name).use(AUTH_PLUGIN, strategy: strategy, **options).plugin(AUTH_PLUGIN)
    end

    def ordered(plugins)
      plugins.sort_by.with_index { |plugin, index| [plugin.class.order_index, index] }
    end

    def entry_for(endpoint, plugins)
      needs_query = needs_query?(endpoint)
      base = Entry.new(
        endpoint: endpoint, status: endpoint.default_status,
        needs_input: needs_query || !endpoint.body_schema.nil?, needs_query: needs_query,
        body_schema: endpoint.body_schema, return_schema: endpoint.return_schema,
        returns_list: endpoint.returns_list?, handler: nil
      )
      return base if plugins.empty?

      base.with(handler: Boto::Plugin::Stack.build(plugins, endpoint_handler(base)))
    end

    def endpoint_handler(entry)
      ->(env) { run(entry, env[PATH_PARAMS_KEY], env) }
    end

    def needs_query?(endpoint)
      !(endpoint.params.names - endpoint.path_param_names).empty?
    end

    def dispatch(env)
      verb = env["REQUEST_METHOD"]
      path = request_path(env)
      match = @router.match(verb, path)
      return unmatched_response(verb, path) unless match

      respond(match, env)
    rescue Boto::Error => e
      e.to_response
    rescue StandardError => e
      internal_error_response(e)
    end

    def respond(match, env)
      entry = match.target
      return run(entry, match.params, env) unless entry.handler

      env[PATH_PARAMS_KEY] = match.params
      entry.handler.call(env)
    end

    def build_openapi_json
      return nil unless @env_name == DEVELOPMENT
      return nil if plugin_named?(@global_plugins, OPENAPI_PLUGIN)

      JSON.generate(Boto::OpenAPI.generate(self, title: title, version: OPENAPI_VERSION)).freeze
    end

    def openapi_request?(verb, path)
      !@openapi_json.nil? && (verb == GET || verb == HEAD) && path == OPENAPI_PATH
    end

    def openapi_response
      [200, { "content-type" => JSON_HEADERS_TYPE }, [@openapi_json]]
    end

    def request_path(env)
      path = env["PATH_INFO"].to_s
      path.empty? ? ROOT_PATH : path
    end

    # Runs only when no route matched, so a user endpoint on OPENAPI_PATH wins and matched requests pay nothing.
    def unmatched_response(verb, path)
      return openapi_response if openapi_request?(verb, path)

      allowed = @router.allowed_verbs(path)
      return Boto::Error::NotFound.new.to_response if allowed.empty?

      Boto::Error::MethodNotAllowed.new(allowed).to_response
    end

    def run(entry, path_params, env)
      args = entry.body_schema ? body_args(entry, path_params, env) : plain_args(entry, path_params, env)
      success_response(entry, entry.endpoint.new(env).call(**args))
    end

    def plain_args(entry, path_params, env)
      query, body = entry.needs_input ? read_input(env) : NO_INPUT
      entry.endpoint.params.call(path: path_params, query: query, body: body)
    end

    # The body is read once, through the schema; params only see the query, so they never touch the body.
    def body_args(entry, path_params, env)
      query = entry.needs_query ? query_hash(env) : EMPTY
      args = entry.endpoint.params.call(path: path_params, query: query, body: EMPTY)
      args.merge(body: coerce_body(entry.body_schema, env))
    end

    def read_input(env)
      [query_hash(env), Boto::RequestBody.parse(env)]
    end

    def query_hash(env)
      Rack::Utils.parse_query(env["QUERY_STRING"].to_s)
    end

    def coerce_body(schema, env)
      schema.coerce(Boto::RequestBody.parse(env))
    rescue Types::Invalid => e
      raise Boto::Error::Unprocessable.new(body_errors(e.errors))
    end

    def body_errors(errors)
      errors.map { |error| { param: error_param(error[:path]), message: error[:message] } }
    end

    def error_param(path)
      path.empty? ? BODY_PARAM : path
    end

    def success_response(entry, result)
      return [NO_CONTENT, {}, []] if result.nil?

      payload = entry.return_schema ? serialize_result(entry, result) : result
      [entry.status, { "content-type" => JSON_HEADERS_TYPE }, [JSON.generate(payload)]]
    end

    def serialize_result(entry, result)
      return entry.return_schema.serialize(result) unless entry.returns_list

      serialize_list(entry, result)
    end

    def serialize_list(entry, result)
      # Any collection with map (Array, ORM relation) is accepted; a Hash would iterate pairs.
      if result.is_a?(Hash) || !result.respond_to?(:map)
        raise Boto::Schema::OutputError, "#{entry.endpoint.name} must return a list"
      end

      result.map { |item| entry.return_schema.serialize(item) }
    end

    def internal_error_response(error)
      log_error(error)
      detail = "#{error.class}: #{error.message}" if @env_name == DEVELOPMENT
      Boto::Problem.response(INTERNAL_ERROR, detail: detail)
    end

    def log_error(error)
      @error_output.puts(["#{error.class}: #{error.message}", *error.backtrace])
    end
  end
end
