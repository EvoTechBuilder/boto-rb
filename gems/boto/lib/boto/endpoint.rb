# frozen_string_literal: true

require "rack/request"

module Boto
  # Base class for one endpoint. Subclasses declare route, params and status at class level,
  # and implement #call with the already-extracted params as keyword arguments.
  class Endpoint
    class RouteError < StandardError; end

    VERBS = %w[GET POST PUT PATCH DELETE].freeze
    DEFAULT_STATUS = 200
    STATUS_RANGE = (100..599)
    DYNAMIC_PREFIX = ":"

    class << self
      def get(path)
        define_route("GET", path)
      end

      def post(path)
        define_route("POST", path)
      end

      def put(path)
        define_route("PUT", path)
      end

      def patch(path)
        define_route("PATCH", path)
      end

      def delete(path)
        define_route("DELETE", path)
      end

      def route
        @route
      end

      def path_param_names
        return [] unless route

        route.last.split("/").filter_map do |segment|
          segment.delete_prefix(DYNAMIC_PREFIX).to_sym if segment.start_with?(DYNAMIC_PREFIX)
        end
      end

      def param(name, type, **options)
        params.declare(name, type, **options)
      end

      def params
        @params ||= Boto::Params.new
      end

      def status(code)
        raise ArgumentError, "invalid status #{code.inspect}" unless valid_status?(code)

        @status = code
      end

      def default_status
        @status || DEFAULT_STATUS
      end

      def compile!
        params.freeze
        self
      end

      private

      def define_route(verb, path)
        raise RouteError, "route already defined: #{route.join(" ")}" if route
        raise ArgumentError, "path must start with /: #{path.inspect}" unless path.is_a?(String) && path.start_with?("/")

        @route = [verb, path].freeze
      end

      def valid_status?(code)
        code.is_a?(Integer) && STATUS_RANGE.cover?(code)
      end
    end

    attr_reader :env

    def initialize(env = {})
      @env = env
    end

    def request
      @request ||= Rack::Request.new(env)
    end

    def call(**)
      raise NotImplementedError, "#{self.class} must implement #call"
    end

    private

    def not_found(detail = nil)
      raise Boto::Error::NotFound.new(detail)
    end

    def bad_request(detail = nil)
      raise Boto::Error::BadRequest.new(detail)
    end

    def unprocessable(errors, detail = nil)
      raise Boto::Error::Unprocessable.new(errors, detail)
    end
  end
end
