# frozen_string_literal: true

module Boto
  module Plugins
    class Auth < Boto::Plugin
      # Checks the HTTP Bearer token against a list of accepted tokens.
      class Bearer
        AUTHORIZATION = "HTTP_AUTHORIZATION"
        PREFIX = "Bearer "
        SECURITY_SCHEME = { "type" => "http", "scheme" => "bearer" }.freeze

        attr_reader :challenge, :security_scheme

        def initialize(tokens:, realm: "Boto")
          @tokens = validate(Boto::Security::Secrets.resolve(tokens))
          @challenge = %(Bearer realm="#{realm}").freeze
          @security_scheme = SECURITY_SCHEME
        end

        def authenticate(env)
          token = bearer_token(env[AUTHORIZATION])
          return unless token

          index = matching_index(token)
          { token_index: index }.freeze if index
        end

        private

        def bearer_token(header)
          header.delete_prefix(PREFIX) if header&.start_with?(PREFIX)
        end

        # Compares against every token, so the position of a match does not show up in timing.
        def matching_index(token)
          @tokens.map { |expected| Boto::Security::Secrets.equal?(token, expected) }.index(true)
        end

        def validate(tokens)
          valid = tokens.is_a?(Array) && !tokens.empty? && tokens.all? { |token| token.is_a?(String) && !token.empty? }
          raise ArgumentError, "tokens must be a non-empty Array of Strings" unless valid

          Boto::Security::Secrets.frozen_copy(tokens)
        end
      end
    end
  end
end
