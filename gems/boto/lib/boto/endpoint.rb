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
    ERROR_STATUS_RANGE = (400..599)
    NO_ERROR_STATUSES = [].freeze
    BODY_MESSAGE = "body must be a Boto::Schema subclass"
    RETURNS_MESSAGE = "returns must be a Boto::Schema subclass or [subclass]"
    SUMMARY_MESSAGE = "summary must be a non-empty String"

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

      def body(schema)
        raise ArgumentError, "body already declared" if @body_schema
        raise ArgumentError, BODY_MESSAGE unless schema_class?(schema)

        @body_schema = schema
      end

      attr_reader :body_schema

      def returns(schema)
        raise ArgumentError, "returns already declared" if @return_schema

        @return_schema = single_return_schema(schema)
        @returns_list = schema.is_a?(Array)
      end

      attr_reader :return_schema

      def returns_list?
        @returns_list == true
      end

      def summary(text)
        raise ArgumentError, SUMMARY_MESSAGE unless text.is_a?(String) && !text.strip.empty?

        @summary_text = text.dup.freeze
      end

      attr_reader :summary_text

      def errors(*statuses)
        statuses.each do |status|
          raise ArgumentError, "invalid error status #{status.inspect}" unless valid_error_status?(status)
        end
        @error_statuses = (error_statuses + statuses).uniq.sort.freeze
      end

      def error_statuses
        @error_statuses || NO_ERROR_STATUSES
      end

      def compile!
        ensure_no_body_conflict!
        params.freeze
        body_schema&.compile!
        return_schema&.compile!
        self
      end

      private

      def single_return_schema(schema)
        candidate = schema.is_a?(Array) && schema.size == 1 ? schema.first : schema
        raise ArgumentError, RETURNS_MESSAGE unless schema_class?(candidate)

        candidate
      end

      def schema_class?(value)
        value.is_a?(Class) && value < Boto::Schema
      end

      def valid_error_status?(code)
        code.is_a?(Integer) && ERROR_STATUS_RANGE.cover?(code)
      end

      def ensure_no_body_conflict!
        return unless body_schema && params.names.include?(:body)

        raise ArgumentError, "#{self}: param :body conflicts with the body schema"
      end

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
