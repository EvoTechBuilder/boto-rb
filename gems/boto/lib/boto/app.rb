# frozen_string_literal: true

require "json"
require "rack/utils"

module Boto
  # Rack app for one project. Discovers the endpoints under a namespace at boot and
  # dispatches each request through a router compiled once.
  class App
    class BootError < StandardError; end

    Entry = Data.define(:endpoint, :status, :needs_input)

    JSON_HEADERS_TYPE = "application/json"
    NO_CONTENT = 204
    INTERNAL_ERROR = 500
    EMPTY = {}.freeze
    NO_INPUT = [EMPTY, EMPTY].freeze
    HEAD = "HEAD"
    ROOT_PATH = "/"
    DEVELOPMENT = "development"

    attr_reader :endpoints

    def initialize(namespace:, env_name: ENV.fetch("BOTO_ENV", "production"), error_output: $stderr)
      @env_name = env_name
      @error_output = error_output
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
    rescue Router::DuplicateRouteError => e
      raise BootError, "#{endpoint.name}: #{e.message}"
    end

    def check_path_params!(endpoint)
      missing = endpoint.path_param_names - endpoint.params.names
      return if missing.empty?

      raise BootError, "#{endpoint.name}: path param :#{missing.first} is not declared"
    end

    def entry_for(endpoint)
      Entry.new(endpoint: endpoint, status: endpoint.default_status, needs_input: needs_input?(endpoint))
    end

    def needs_input?(endpoint)
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
      query, body = entry.needs_input ? read_input(env) : NO_INPUT
      args = entry.endpoint.params.call(path: path_params, query: query, body: body)
      success_response(entry, entry.endpoint.new(env).call(**args))
    end

    def read_input(env)
      [Rack::Utils.parse_query(env["QUERY_STRING"].to_s), Boto::RequestBody.parse(env)]
    end

    def success_response(entry, result)
      return [NO_CONTENT, {}, []] if result.nil?

      [entry.status, { "content-type" => JSON_HEADERS_TYPE }, [JSON.generate(result)]]
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
