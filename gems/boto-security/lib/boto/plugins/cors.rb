# frozen_string_literal: true

module Boto
  module Plugins
    # Answers CORS preflights and adds CORS headers to responses for allowed origins.
    class Cors < Boto::Plugin
      scope :global

      DEFAULT_METHODS = %w[GET HEAD POST PUT PATCH DELETE QUERY].freeze
      DEFAULT_HEADERS = %w[content-type authorization].freeze
      EMPTY_LIST = [].freeze
      ANY_ORIGIN = "*"
      LIST_SEPARATOR = ", "
      TRUE_VALUE = "true"

      ORIGIN_ENV = "HTTP_ORIGIN"
      REQUESTED_METHOD_ENV = "HTTP_ACCESS_CONTROL_REQUEST_METHOD"
      REQUEST_METHOD_ENV = "REQUEST_METHOD"
      PREFLIGHT_METHOD = "OPTIONS"
      PREFLIGHT_STATUS = 204

      ALLOW_ORIGIN = "access-control-allow-origin"
      ALLOW_METHODS = "access-control-allow-methods"
      ALLOW_HEADERS = "access-control-allow-headers"
      ALLOW_CREDENTIALS = "access-control-allow-credentials"
      EXPOSE_HEADERS = "access-control-expose-headers"
      MAX_AGE = "access-control-max-age"
      VARY = "vary"
      VARY_ORIGIN = "Origin"

      def call(env, app)
        origin = env[ORIGIN_ENV]
        return app.call(env) unless origin
        return preflight(env, origin) if preflight?(env)
        return app.call(env) unless allowed_origin?(origin)

        status, headers, body = app.call(env)
        [status, with_response_headers(headers, origin), body]
      end

      private

      def configure(origins: EMPTY_LIST, methods: DEFAULT_METHODS, headers: DEFAULT_HEADERS,
                    expose: EMPTY_LIST, credentials: false, max_age: nil)
        @any_origin = origins == ANY_ORIGIN
        raise ArgumentError, 'cors: origins "*" cannot be used with credentials' if @any_origin && credentials

        @origins = @any_origin ? EMPTY_LIST : parse_origins(origins)
        validate_max_age!(max_age)
        @credentials = credentials
        @allowed_methods = methods.map { |name| name.upcase.freeze }.freeze
        @preflight_headers = build_preflight_headers(headers, max_age)
        @response_headers = build_response_headers(expose)
      end

      def parse_origins(origins)
        unless origins.is_a?(Array) && origins.all? { |origin| valid_origin?(origin) }
          raise ArgumentError, 'cors: origins must be an Array of origin Strings or "*"'
        end

        # Browsers send scheme and host in lowercase, so configured origins are normalized to match.
        origins.map { |origin| -origin.downcase }.freeze
      end

      def valid_origin?(value)
        value.is_a?(String) && !value.empty? && value != ANY_ORIGIN
      end

      def validate_max_age!(max_age)
        return if max_age.nil? || (max_age.is_a?(Integer) && max_age >= 0)

        raise ArgumentError, "cors: max_age must be a non-negative Integer or nil"
      end

      def build_preflight_headers(headers, max_age)
        {
          ALLOW_METHODS => @allowed_methods.join(LIST_SEPARATOR),
          ALLOW_HEADERS => headers.join(LIST_SEPARATOR),
          MAX_AGE => max_age&.to_s,
          ALLOW_CREDENTIALS => (TRUE_VALUE if @credentials),
          VARY => VARY_ORIGIN
        }.compact.freeze
      end

      def build_response_headers(expose)
        {
          EXPOSE_HEADERS => (expose.join(LIST_SEPARATOR) unless expose.empty?),
          ALLOW_CREDENTIALS => (TRUE_VALUE if @credentials)
        }.compact.freeze
      end

      def preflight?(env)
        env[REQUEST_METHOD_ENV] == PREFLIGHT_METHOD && env.key?(REQUESTED_METHOD_ENV)
      end

      def preflight(env, origin)
        return rejected_preflight unless allowed_origin?(origin) && @allowed_methods.include?(env[REQUESTED_METHOD_ENV])

        [PREFLIGHT_STATUS, @preflight_headers.merge(ALLOW_ORIGIN => allow_origin(origin)), []]
      end

      def rejected_preflight
        Boto::Error::Forbidden.new("CORS preflight rejected").to_response
      end

      def allowed_origin?(origin)
        @any_origin || @origins.include?(origin)
      end

      def allow_origin(origin)
        @any_origin ? ANY_ORIGIN : origin
      end

      def with_response_headers(headers, origin)
        result = headers.frozen? ? headers.dup : headers
        result[ALLOW_ORIGIN] = allow_origin(origin)
        result[VARY] = merge_vary(result[VARY])
        @response_headers.each { |name, value| result[name] = value }
        result
      end

      def merge_vary(existing)
        return VARY_ORIGIN if existing.nil? || existing.empty?
        return existing if existing.split(",").any? { |field| field.strip.casecmp?(VARY_ORIGIN) }

        "#{existing}#{LIST_SEPARATOR}#{VARY_ORIGIN}"
      end
    end
  end
end
