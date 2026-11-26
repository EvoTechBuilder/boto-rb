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
  end
end
