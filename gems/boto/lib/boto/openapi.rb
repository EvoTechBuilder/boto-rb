# frozen_string_literal: true

require "rack/utils"

module Boto
  # Builds an OpenAPI 3.1 document from an app's endpoints and schemas. Pure: it reads the
  # declarations and returns a Hash, without IO, so it runs at boot or from a CLI command.
  module OpenAPI
    SPEC_VERSION = "3.1.0"
    # OpenAPI 3.1 has no QUERY operation; 3.2.0 adds the Path Item `query` field.
    QUERY_SPEC_VERSION = "3.2.0"
    QUERY_VERB = "QUERY"
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
    UNAUTHORIZED = 401
    UNPROCESSABLE = 422
    UNKNOWN_STATUS_TITLE = "Unknown Status"
    CAMEL_WORD_BOUNDARY = /([a-z\d])([A-Z])/
    CAMEL_ACRONYM_BOUNDARY = /([A-Z]+)([A-Z][a-z])/
    SNAKE_JOIN = '\1_\2'

    def self.generate(app, title:, version:)
      endpoints = app.endpoints
      guards = endpoints.to_h { |endpoint| [endpoint, app.auth_for(endpoint)] }
      {
        "openapi" => spec_version(endpoints),
        "info" => { "title" => title, "version" => version },
        "paths" => paths(endpoints, guards),
        "components" => components(endpoints, guards)
      }
    end

    def self.paths(endpoints, guards)
      sorted = endpoints.sort_by { |endpoint| [endpoint.route.last, endpoint.route.first] }
      secured = guards.each_value.any?
      sorted.each_with_object({}) do |endpoint, result|
        verb, path = endpoint.route
        operation = Operation.new(endpoint, auth: guards[endpoint], secured: secured).to_h
        (result[openapi_path(path)] ||= {})[verb.downcase] = operation
      end
    end

    # The name of a strategy's security scheme: its class name in snake_case (Auth::ApiKey -> "api_key").
    def self.scheme_name(strategy)
      class_name = strategy.class.name.split(NAMESPACE_SEPARATOR).last
      class_name.gsub(CAMEL_ACRONYM_BOUNDARY, SNAKE_JOIN).gsub(CAMEL_WORD_BOUNDARY, SNAKE_JOIN).downcase
    end

    def self.components(endpoints, guards)
      components = { "schemas" => schemas(endpoints) }
      schemes = security_schemes(guards.values.compact)
      components["securitySchemes"] = schemes unless schemes.empty?
      components
    end

    def self.security_schemes(auths)
      auths.map { |auth| [scheme_name(auth.strategy), auth.strategy.security_scheme] }
           .uniq.sort_by(&:first).to_h
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

    def self.spec_version(endpoints)
      endpoints.any? { |endpoint| endpoint.route.first == QUERY_VERB } ? QUERY_SPEC_VERSION : SPEC_VERSION
    end

    private_class_method :spec_version
  end
end
