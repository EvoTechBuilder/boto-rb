# frozen_string_literal: true

require "rack/utils"

module Boto
  # Builds an OpenAPI 3.1 document from an app's endpoints and schemas. Pure: it reads the
  # declarations and returns a Hash, without IO, so it runs at boot or from a CLI command.
  module OpenAPI
    SPEC_VERSION = "3.1.0"
    JSON_CONTENT = "application/json"
    PROBLEM_CONTENT = "application/problem+json"
    PROBLEM_SCHEMA_NAME = "Problem"
    PROBLEM_REF = { "$ref" => "#/components/schemas/#{PROBLEM_SCHEMA_NAME}" }.freeze
    PROBLEM_SCHEMA = {
      "type" => "object",
      "properties" => {
        "type" => { "type" => "string" },
        "title" => { "type" => "string" },
        "status" => { "type" => "integer" },
        "detail" => { "type" => "string" },
        "errors" => {
          "type" => "array",
          "items" => {
            "type" => "object",
            "properties" => { "param" => { "type" => "string" }, "message" => { "type" => "string" } }
          }
        }
      },
      "required" => %w[type title status]
    }.freeze

    PATH_PARAM = /:(\w+)/
    PATH_PARAM_TEMPLATE = '{\1}'
    NAMESPACE_SEPARATOR = "::"
    PATH_LOCATION = "path"
    QUERY_LOCATION = "query"
    ARRAY_TYPE = "array"
    NO_CONTENT = 204
    NOT_FOUND = 404
    UNPROCESSABLE = 422
    UNKNOWN_STATUS_TITLE = "Unknown Status"

    def self.generate(app, title:, version:)
      endpoints = app.endpoints
      {
        "openapi" => SPEC_VERSION,
        "info" => { "title" => title, "version" => version },
        "paths" => paths(endpoints),
        "components" => { "schemas" => schemas(endpoints) }
      }
    end

    def self.paths(endpoints)
      sorted = endpoints.sort_by { |endpoint| [endpoint.route.last, endpoint.route.first] }
      sorted.each_with_object({}) do |endpoint, result|
        verb, path = endpoint.route
        (result[openapi_path(path)] ||= {})[verb.downcase] = Operation.new(endpoint).to_h
      end
    end

    def self.openapi_path(path)
      path.gsub(PATH_PARAM, PATH_PARAM_TEMPLATE)
    end

    def self.schemas(endpoints)
      roots = endpoints.flat_map { |endpoint| [endpoint.body_schema, endpoint.return_schema] }.compact
      named = SchemaCatalog.collect(roots).transform_values(&:json_schema)
      raise ArgumentError, "schema name #{PROBLEM_SCHEMA_NAME} is reserved for errors" if named.key?(PROBLEM_SCHEMA_NAME)

      named.merge(PROBLEM_SCHEMA_NAME => PROBLEM_SCHEMA).sort_by(&:first).to_h
    end

    # Every schema reachable from the roots, once each, keyed by schema_name.
    class SchemaCatalog
      def self.collect(roots)
        found = {}
        pending = roots.dup
        until pending.empty?
          schema = pending.shift
          existing = found[schema.schema_name]
          next if existing.equal?(schema)
          raise ArgumentError, "two different schemas are named #{schema.schema_name}" if existing

          found[schema.schema_name] = schema
          pending.concat(nested_schemas(schema))
        end
        found
      end

      # Schema#nested_schemas is private, so the fields are read here through the public API.
      def self.nested_schemas(schema)
        schema.fields.flat_map { |field| [field.declared_type].flatten }.select do |type|
          Types::SchemaRef.schema?(type)
        end
      end

      private_class_method :nested_schemas
    end

    # The operation object of one endpoint: its parameters, body and responses.
    class Operation
      def initialize(endpoint)
        @endpoint = endpoint
      end

      def to_h
        operation = { "operationId" => operation_id }
        operation["summary"] = @endpoint.summary_text if @endpoint.summary_text
        operation["parameters"] = parameters unless definitions.empty?
        operation["requestBody"] = request_body if @endpoint.body_schema
        operation["responses"] = responses
        operation
      end

      private

      def operation_id
        @endpoint.name.split(NAMESPACE_SEPARATOR).drop(1).join
      end

      def definitions
        @endpoint.params.definitions
      end

      def parameters
        definitions.map { |definition| parameter(definition) }
      end

      def parameter(definition)
        path = path_param_names.include?(definition.name)
        {
          "name" => definition.key,
          "in" => path ? PATH_LOCATION : QUERY_LOCATION,
          "required" => path || definition.required,
          "schema" => parameter_schema(definition)
        }
      end

      def parameter_schema(definition)
        schema = definition.type.json_schema
        return schema if definition.default.equal?(Params::MISSING)

        schema.merge("default" => definition.default)
      end

      def request_body
        { "required" => true, "content" => { JSON_CONTENT => { "schema" => @endpoint.body_schema.json_schema_ref } } }
      end

      def responses
        result = { status.to_s => success_response }
        error_codes.each { |code| result[code.to_s] = problem_response(code) }
        result
      end

      def status
        @endpoint.default_status
      end

      def success_response
        response = { "description" => title_for(status) }
        return response if status == NO_CONTENT

        response.merge("content" => { JSON_CONTENT => { "schema" => response_schema } })
      end

      def response_schema
        schema = @endpoint.return_schema
        return {} unless schema

        ref = schema.json_schema_ref
        @endpoint.returns_list? ? { "type" => ARRAY_TYPE, "items" => ref } : ref
      end

      def error_codes
        (@endpoint.error_statuses + implicit_error_codes).uniq.sort
      end

      def implicit_error_codes
        [(UNPROCESSABLE if validated?), (NOT_FOUND unless path_param_names.empty?)].compact
      end

      def validated?
        !definitions.empty? || !@endpoint.body_schema.nil?
      end

      def path_param_names
        @endpoint.path_param_names
      end

      def problem_response(code)
        { "description" => title_for(code), "content" => { PROBLEM_CONTENT => { "schema" => PROBLEM_REF } } }
      end

      def title_for(code)
        Rack::Utils::HTTP_STATUS_CODES.fetch(code, UNKNOWN_STATUS_TITLE)
      end
    end
  end
end
