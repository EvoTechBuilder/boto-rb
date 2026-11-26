# frozen_string_literal: true

require "jwt"
require "openssl"

module Boto
  module Plugins
    class Auth < Boto::Plugin
      # Bearer JWT strategy: the verified claims become the principal.
      class Jwt
        AUTHORIZATION_KEY = "HTTP_AUTHORIZATION"
        BEARER_PREFIX = "Bearer "
        NONE_ALGORITHM = "none"
        REQUIRED_CLAIMS = ["exp"].freeze
        DEFAULT_REALM = "Boto"

        def initialize(algorithms:, secret: nil, public_key: nil, issuer: nil, audience: nil, leeway: 0, realm: DEFAULT_REALM)
          @algorithms = validate_algorithms(algorithms)
          @key = load_key(secret, public_key)
          @decode_options = build_decode_options(issuer, audience, validate_leeway(leeway))
          @realm = Boto::Security::Secrets.frozen_copy(realm)
        end

        def authenticate(env)
          token = bearer_token(env)
          return unless token

          payload, _header = JWT.decode(token, @key, true, @decode_options)
          payload.transform_keys(&:to_sym).freeze
        rescue JWT::DecodeError
          nil
        end

        def challenge
          %(Bearer realm="#{@realm}")
        end

        def security_scheme
          { "type" => "http", "scheme" => "bearer", "bearerFormat" => "JWT" }
        end

        private

        def validate_algorithms(algorithms)
          unless algorithms.is_a?(Array) && !algorithms.empty? && algorithms.all?(String)
            raise ArgumentError, "algorithms deve ser um Array não vazio de Strings"
          end
          raise ArgumentError, "o algoritmo 'none' não é aceito" if algorithms.any? { _1.casecmp?(NONE_ALGORITHM) }

          Boto::Security::Secrets.frozen_copy(algorithms)
        end

        def load_key(secret, public_key)
          raise ArgumentError, "informe secret ou public_key, exatamente um" if secret.nil? == public_key.nil?

          secret ? frozen_secret(secret) : parse_public_key(Boto::Security::Secrets.resolve(public_key))
        end

        def frozen_secret(secret)
          Boto::Security::Secrets.frozen_copy(Boto::Security::Secrets.resolve(secret))
        end

        def parse_public_key(key)
          key.is_a?(String) ? OpenSSL::PKey.read(key) : key
        end

        def validate_leeway(leeway)
          raise ArgumentError, "leeway deve ser um Integer >= 0" unless leeway.is_a?(Integer) && leeway >= 0

          leeway
        end

        def build_decode_options(issuer, audience, leeway)
          {
            algorithms: @algorithms,
            leeway: leeway,
            iss: Boto::Security::Secrets.frozen_copy(issuer),
            verify_iss: !issuer.nil?,
            aud: Boto::Security::Secrets.frozen_copy(audience),
            verify_aud: !audience.nil?,
            required_claims: REQUIRED_CLAIMS
          }.freeze
        end

        def bearer_token(env)
          header = env[AUTHORIZATION_KEY]
          return unless header&.start_with?(BEARER_PREFIX)

          header.delete_prefix(BEARER_PREFIX)
        end
      end
    end
  end
end
