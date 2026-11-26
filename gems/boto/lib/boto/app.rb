# frozen_string_literal: true

require "json"
require "rack/utils"

module Boto
  # Rack app for one project. Discovers the endpoints under a namespace at boot and
  # dispatches each request through a router compiled once.
  class App
    class BootError < StandardError; end

    Entry = Data.define(:endpoint, :status, :needs_input, :needs_query, :body_schema, :return_schema, :returns_list)

    JSON_HEADERS_TYPE = "application/json"
    NO_CONTENT = 204
    INTERNAL_ERROR = 500
    EMPTY = {}.freeze
    NO_INPUT = [EMPTY, EMPTY].freeze
    HEAD = "HEAD"
    ROOT_PATH = "/"
    DEVELOPMENT = "development"
    BODY_PARAM = "body"

    attr_reader :endpoints, :title

    def initialize(namespace:, env_name: ENV.fetch("BOTO_ENV", "production"), error_output: $stderr)
      @env_name = env_name
      @error_output = error_output
      @title = namespace.name.freeze
      @router = Router.new
      @endpoints = discover(namespace).each { |endpoint| register(endpoint) }.freeze
      @router.compile
    end

    def call(env)
      response = dispatch(env)
      env["REQUEST_METHOD"] == HEAD ? [response[0], response[1], []] : response
    end

    private

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
      @router.add(*endpoint.route, entry_for(endpoint))
    rescue Router::DuplicateRouteError, ArgumentError => e
      raise BootError, "#{endpoint.name}: #{e.message}"
    end

    def check_path_params!(endpoint)
      missing = endpoint.path_param_names - endpoint.params.names
      return if missing.empty?

      raise BootError, "#{endpoint.name}: path param :#{missing.first} is not declared"
    end

    def entry_for(endpoint)
      needs_query = needs_query?(endpoint)
      Entry.new(
        endpoint: endpoint, status: endpoint.default_status,
        needs_input: needs_query || !endpoint.body_schema.nil?, needs_query: needs_query,
        body_schema: endpoint.body_schema, return_schema: endpoint.return_schema,
        returns_list: endpoint.returns_list?
      )
    end

    def needs_query?(endpoint)
      !(endpoint.params.names - endpoint.path_param_names).empty?
    end

    def dispatch(env)
      verb = env["REQUEST_METHOD"]
      path = request_path(env)
      match = @router.match(verb, path)
      return unmatched_response(path) unless match

      run(match.target, match.params, env)
    rescue Boto::Error => e
      e.to_response
    rescue StandardError => e
      internal_error_response(e)
    end

    def request_path(env)
      path = env["PATH_INFO"].to_s
      path.empty? ? ROOT_PATH : path
    end

    def unmatched_response(path)
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
