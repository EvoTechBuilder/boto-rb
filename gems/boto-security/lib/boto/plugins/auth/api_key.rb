# frozen_string_literal: true

module Boto
  module Plugins
    class Auth < Boto::Plugin
      # Checks an API key sent in a request header against a Hash of key_id => key.
      class ApiKey
        attr_reader :challenge, :security_scheme

        def initialize(keys:, header: "X-API-Key")
          @keys = validate_keys(Boto::Security::Secrets.resolve(keys))
          @rack_key = rack_key_for(header)
          @challenge = %(API-Key header="#{header}").freeze
          @security_scheme = { "type" => "apiKey", "in" => "header", "name" => header }.freeze
        end

        def authenticate(env)
          given = env[@rack_key]
          return unless given

          # Compares against every key, so the position of a match does not show up in timing.
          found = @keys.map { |id, key| [id, Boto::Security::Secrets.equal?(given, key)] }.find { |_id, matched| matched }
          { key_id: found.first }.freeze if found
        end

        private

        def validate_keys(keys)
          valid = keys.is_a?(Hash) && !keys.empty? && keys.values.all? { |key| key.is_a?(String) && !key.empty? }
          raise ArgumentError, "keys must be a non-empty Hash of key_id => key" unless valid

          keys.dup.freeze
        end

        def rack_key_for(header)
          raise ArgumentError, "header must be a non-empty String" unless header.is_a?(String) && !header.empty?

          "HTTP_#{header.upcase.tr("-", "_")}".freeze
        end
      end
    end
  end
end
