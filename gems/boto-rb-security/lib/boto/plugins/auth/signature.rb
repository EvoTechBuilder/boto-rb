# frozen_string_literal: true

require "openssl"
require "stringio"

module Boto
  module Plugins
    class Auth < Boto::Plugin
      # HMAC webhook strategy: the signature of the raw body (optionally bound to a timestamp) must match.
      class Signature
        ALGORITHMS = %w[sha256 sha512].freeze
        DEFAULT_HEADER = "X-Signature"
        DEFAULT_ALGORITHM = "sha256"
        DEFAULT_TIMESTAMP_HEADER = "X-Timestamp"
        RACK_HTTP_PREFIX = "HTTP_"
        RACK_INPUT = "rack.input"
        TIMESTAMP_FORMAT = /\A\d+\z/
        PRINCIPAL = { signed: true }.freeze
        SIGNED_MESSAGE_SEPARATOR = "."

        def initialize(secret:, header: DEFAULT_HEADER, algorithm: DEFAULT_ALGORITHM, prefix: nil,
                       tolerance: nil, timestamp_header: DEFAULT_TIMESTAMP_HEADER,
                       clock: -> { Time.now.to_i })
          @secret = validate_secret(Boto::Security::Secrets.resolve(secret))
          @algorithm = validate_algorithm(algorithm)
          @tolerance = validate_tolerance(tolerance)
          @header = Boto::Security::Secrets.frozen_copy(header)
          @signature_key = rack_key(header)
          @timestamp_key = rack_key(timestamp_header)
          @prefix = Boto::Security::Secrets.frozen_copy(prefix)
          @clock = clock
        end

        def authenticate(env)
          given = signature_from(env)
          return unless given

          message = signed_message(env, read_body(env))
          return unless message

          expected = OpenSSL::HMAC.hexdigest(@algorithm, @secret, message)
          Boto::Security::Secrets.equal?(given, expected) ? PRINCIPAL : nil
        end

        def challenge
          %(Signature header="#{@header}")
        end

        def security_scheme
          { "type" => "apiKey", "in" => "header", "name" => @header }
        end

        # The body is read here, before the endpoint, so an oversized one is answered with 413.
        def error_statuses = [Boto::Error::PayloadTooLarge::STATUS]

        private

        def validate_secret(secret)
          raise ArgumentError, "secret deve ser uma String não vazia" unless secret.is_a?(String) && !secret.empty?

          Boto::Security::Secrets.frozen_copy(secret)
        end

        def validate_algorithm(algorithm)
          raise ArgumentError, "algorithm deve ser #{ALGORITHMS.join(" ou ")}" unless ALGORITHMS.include?(algorithm)

          Boto::Security::Secrets.frozen_copy(algorithm)
        end

        def validate_tolerance(tolerance)
          return tolerance if tolerance.nil? || (tolerance.is_a?(Integer) && tolerance.positive?)

          raise ArgumentError, "tolerance deve ser nil ou um Integer > 0"
        end

        def rack_key(header)
          "#{RACK_HTTP_PREFIX}#{header.upcase.tr("-", "_")}"
        end

        def signature_from(env)
          value = env[@signature_key]
          return value unless @prefix && value

          value.delete_prefix(@prefix) if value.start_with?(@prefix)
        end

        def read_body(env)
          body = Boto::RequestBody.read(env)
          restore_input(env, body)
          body
        end

        # Lets the downstream app read the body again: rewinds rewindable inputs, replaces the others.
        def restore_input(env, body)
          input = env[RACK_INPUT]
          return unless input

          if input.respond_to?(:rewind)
            input.rewind
          else
            env[RACK_INPUT] = StringIO.new(body)
          end
        end

        def signed_message(env, body)
          return body unless @tolerance

          timestamp = timestamp_from(env)
          return unless timestamp && (@clock.call - timestamp).abs <= @tolerance

          [timestamp, body].join(SIGNED_MESSAGE_SEPARATOR)
        end

        def timestamp_from(env)
          value = env[@timestamp_key].to_s
          value.to_i if value.match?(TIMESTAMP_FORMAT)
        end
      end
    end
  end
end
