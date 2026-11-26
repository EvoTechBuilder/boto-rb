# frozen_string_literal: true

module Boto
  module OpenAPI
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
