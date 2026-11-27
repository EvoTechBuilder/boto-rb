# frozen_string_literal: true

module Boto
  module Gateway
    # Decides the prefix of each referenced service and checks the result, once at boot.
    class Mounts
      ROOT = "/"
      RESERVED_PREFIX = "/_boto"
      ERROR_PREFIX = "gateway: "

      # [service name, prefix, app] for every service, in the order the app received them.
      attr_reader :entries

      def initialize(services:, prefixes: {})
        prefixes = prefixes.transform_keys(&:to_s) # app.use :gateway, prefixes: { users: "/contas" } works too
        check_names!(services, prefixes)
        @entries = services.map { |name, app| [name, prefix_for(name, prefixes), app] }.freeze
        check_unique_prefixes!
      end

      # The Hash that Rack::URLMap takes: prefix => app.
      def apps_by_prefix
        @entries.to_h { |_name, prefix, app| [prefix, app] }
      end

      private

      def check_names!(services, prefixes)
        unknown = prefixes.keys - services.keys
        return if unknown.empty?

        raise ArgumentError, "#{ERROR_PREFIX}prefixes names #{unknown.map(&:inspect).join(", ")}, which is not a ref"
      end

      def prefix_for(name, prefixes)
        prefix = prefixes.fetch(name) { "#{ROOT}#{name}" }
        reason = prefix_problem(prefix)
        raise ArgumentError, "#{ERROR_PREFIX}prefix of #{name.inspect} #{reason}, got #{prefix.inspect}" if reason

        prefix
      end

      def prefix_problem(prefix)
        return "must be a String" unless prefix.is_a?(String)
        return "must start with \"/\"" unless prefix.start_with?(ROOT)
        return "cannot be \"/\"" if prefix == ROOT
        return "cannot end with \"/\"" if prefix.end_with?(ROOT)
        return "cannot start with \"/_boto\", which is reserved for the panel" if prefix.start_with?(RESERVED_PREFIX)

        nil
      end

      def check_unique_prefixes!
        seen = {}
        @entries.each do |name, prefix, _app|
          raise ArgumentError, duplicate_message(name, prefix) if seen.key?(prefix)

          seen[prefix] = name
        end
      end

      def duplicate_message(name, prefix)
        "#{ERROR_PREFIX}prefix #{prefix.inspect} of #{name.inspect} is used by another service"
      end
    end
  end
end
