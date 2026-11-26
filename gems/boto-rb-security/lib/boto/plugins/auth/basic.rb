# frozen_string_literal: true

module Boto
  module Plugins
    class Auth < Boto::Plugin
      # Checks HTTP Basic credentials against a Hash of user => password.
      class Basic
        AUTHORIZATION = "HTTP_AUTHORIZATION"
        PREFIX = "Basic "
        # Compared when the user is unknown, so a miss takes about as long as a wrong password.
        DUMMY_PASSWORD = "boto-unknown-user"
        SECURITY_SCHEME = { "type" => "http", "scheme" => "basic" }.freeze

        attr_reader :challenge, :security_scheme

        def initialize(credentials:, realm: "Boto")
          @credentials = validate(Boto::Security::Secrets.resolve(credentials))
          @challenge = %(Basic realm="#{realm}").freeze
          @security_scheme = SECURITY_SCHEME
        end

        def authenticate(env)
          user, password = decode(env[AUTHORIZATION])
          return unless password

          matched = Boto::Security::Secrets.equal?(password, @credentials.fetch(user, DUMMY_PASSWORD))
          { user: user }.freeze if matched && @credentials.key?(user)
        end

        private

        def decode(header)
          return unless header&.start_with?(PREFIX)

          # split needs binary input: it raises on invalid UTF-8 bytes sent by a client
          header.delete_prefix(PREFIX).unpack1("m").split(":", 2).map { |part| part.force_encoding(Encoding::UTF_8) }
        end

        def validate(credentials)
          valid = credentials.is_a?(Hash) && !credentials.empty? &&
                  credentials.all? { |user, password| user.is_a?(String) && password.is_a?(String) && !password.empty? }
          raise ArgumentError, "credentials must be a non-empty Hash of user => password" unless valid

          Boto::Security::Secrets.frozen_copy(credentials)
        end
      end
    end
  end
end
