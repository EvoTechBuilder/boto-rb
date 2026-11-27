# frozen_string_literal: true

require "uri"

module Boto
  module Gateway
    # Hides secrets before the panel or its JSON shows a variable. Pure: it returns the value to show and a flag.
    module Masking
      MASK = "••••••••"
      SENSITIVE_WORDS = %w[PASSWORD SECRET TOKEN KEY DSN CREDENTIAL].freeze
      SENSITIVE_NAME = Regexp.new(SENSITIVE_WORDS.join("|"), Regexp::IGNORECASE).freeze

      module_function

      # Returns [shown_value, masked]. The whole value goes for sensitive names; a URL keeps everything but its password.
      def apply(name, value)
        return [MASK, true] if SENSITIVE_NAME.match?(name)

        url = mask_url_password(value)
        return [url, true] if url

        [value, false]
      end

      def mask_url_password(value)
        password = url_password(value)
        return if password.nil? || password.empty?

        value.sub(":#{password}@") { ":#{MASK}@" }
      end

      # A value that is not a URI (spaces, stray %) has no password to hide.
      def url_password(value)
        URI.parse(value).password
      rescue URI::InvalidURIError
        nil
      end
    end
  end
end
