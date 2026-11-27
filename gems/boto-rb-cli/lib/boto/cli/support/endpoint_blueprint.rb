# frozen_string_literal: true

module Boto
  module CLI
    # Renders an endpoint and its test. Path params take the type of their field, and String when none is given.
    class EndpointBlueprint < Blueprint
      KIND = "endpoint"
      DEFAULT_PARAM_TYPE = "string"
      PARAM_PLACEHOLDER = "1"
      QUERY_VERB = "query"
      INPUT_VERBS = %w[post put patch query].freeze
      JSON_CONTENT_TYPE = "application/json"
      # The token the webapi test_helper puts in API_TOKENS.
      TEST_TOKEN = "test-token"

      attr_reader :route

      def initialize(name:, namespace:, route:, fields:, body:, returns:, auth:)
        @namespace = namespace
        @route = route
        @auth = auth
        super(KIND, name: name, fields: path_params(fields), namespace: namespace)
        @body_source = body && schema_constant(body)
        @returns_source = returns && returns_constant(returns)
      end

      private

      def path_params(fields)
        ensure_path_fields!(fields)
        route.param_names.map { |param| typed_param(param, fields) }
      end

      def typed_param(param, fields)
        field = fields.find { _1.name == param } ||
                FieldSpec.parse("#{param}:#{DEFAULT_PARAM_TYPE}", namespace: @namespace)
        return field if field.scalar?

        raise Error, %(path param "#{param}" must be a scalar type (#{FieldSpec::TYPES.keys.join(", ")}))
      end

      def ensure_path_fields!(fields)
        unknown = fields.find { !route.param_names.include?(_1.name) }
        return unless unknown

        raise Error, %(field "#{unknown.name}" is not a path param of #{route.path})
      end

      def schema_constant(name)
        ConstantName.new(name, namespace: @namespace).with_suffix(FieldSpec::SCHEMA_SUFFIX).constant
      end

      def returns_constant(returns)
        match = FieldSpec::LIST.match(returns)
        return "[#{schema_constant(match[1])}]" if match

        schema_constant(returns)
      end

      def locals
        super.merge(
          verb: route.verb, path: route.path, params: fields, body_source: @body_source,
          returns_source: @returns_source, signature: signature, test_name: test_name,
          request_call: request_call, http_verb: route.verb.upcase
        )
      end

      def signature
        keywords = [*route.param_names.map { "#{_1}:" }, *("body:" if @body_source)]
        keywords.empty? ? "" : "(#{keywords.join(", ")})"
      end

      def test_name
        slug = route.path.downcase.gsub(/[^a-z0-9]+/, "_").delete_prefix("_").delete_suffix("_")
        [route.verb, slug].reject(&:empty?).join("_")
      end

      def request_call
        args = [%("#{request_path}"), *request_options].join(", ")
        return %(Rack::MockRequest.new(APP).request("QUERY", #{args})) if route.verb == QUERY_VERB

        "Rack::MockRequest.new(APP).#{route.verb}(#{args})"
      end

      def request_path = route.path.gsub(/:\w+/, PARAM_PLACEHOLDER)

      def request_options
        options = []
        options << %(input: "{}") if INPUT_VERBS.include?(route.verb)
        options << %("CONTENT_TYPE" => "#{JSON_CONTENT_TYPE}") if @body_source
        options << %("HTTP_AUTHORIZATION" => "Bearer #{TEST_TOKEN}") if @auth
        options
      end
    end
  end
end
