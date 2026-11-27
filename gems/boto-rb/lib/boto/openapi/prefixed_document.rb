# frozen_string_literal: true

require "json"

module Boto
  module OpenAPI
    # Serves one document JSON per mount prefix (SCRIPT_NAME), with `servers` pointing at the prefix.
    class PrefixedDocument
      SERVERS = "servers"
      EMPTY_PREFIX = ""

      def initialize(document)
        @document = document
        @plain_json = JSON.generate(document).freeze
        # Few prefixes in practice: one per gateway that mounts the app.
        @json_by_prefix = {}
      end

      def json_for(script_name)
        return @plain_json if script_name.nil? || script_name == EMPTY_PREFIX

        @json_by_prefix[script_name] ||= JSON.generate(with_servers(script_name)).freeze
      end

      private

      def with_servers(script_name)
        @document.merge(SERVERS => [{ "url" => script_name }])
      end
    end
  end
end
