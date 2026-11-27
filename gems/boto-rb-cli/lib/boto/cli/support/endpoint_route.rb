# frozen_string_literal: true

module Boto
  module CLI
    # The verb and path of an endpoint. Checked before any file is rendered, so a bad route never reaches the code.
    class EndpointRoute < Data.define(:verb, :path)
      VERBS = %w[get post put patch delete query].freeze
      # Only these characters are safe inside the generated double-quoted route string.
      PATH = %r{\A/[A-Za-z0-9_\-/:.]*\z}
      PARAM_PREFIX = ":"

      def self.parse(verb, path)
        raise Error, %(unknown verb "#{verb}" (available: #{VERBS.join(", ")})) unless VERBS.include?(verb)
        raise Error, %(invalid path "#{path}" (start with / and use letters, digits, _ - / : .)) unless
          PATH.match?(path)

        route = new(verb: verb, path: path)
        route.param_names.each { |param| ensure_param_name!(param, path) }
        route
      end

      def self.ensure_param_name!(param, path)
        return if FieldSpec::IDENTIFIER.match?(param)

        raise Error, %(invalid path param "#{PARAM_PREFIX}#{param}" in #{path})
      end

      private_class_method :ensure_param_name!

      def param_names
        path.split("/").select { _1.start_with?(PARAM_PREFIX) }.map { _1.delete_prefix(PARAM_PREFIX) }
      end
    end
  end
end
