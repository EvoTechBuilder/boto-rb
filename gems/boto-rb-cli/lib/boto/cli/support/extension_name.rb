# frozen_string_literal: true

module Boto
  module CLI
    # Names of an extension gem, derived from its gem name: boto-rb-gateway -> gateway -> Boto::Gateway.
    class ExtensionName
      GEM_FORMAT = /\A[a-z0-9][a-z0-9_-]*\z/
      NAME_FORMAT = /\A[a-z][a-z0-9_]*\z/
      # Longest first: "boto-" alone would turn "boto-rb-gateway" into "rb-gateway".
      PREFIXES = %w[boto-rb- boto-].freeze
      SEPARATOR = "_"

      attr_reader :gem_name, :extension

      def self.check_name!(kind, name)
        return if NAME_FORMAT.match?(name)

        raise Error, %(invalid #{kind} name "#{name}": use lowercase letters, digits and "_", starting with a letter)
      end

      def self.camelize(name) = name.split(SEPARATOR).map(&:capitalize).join

      def initialize(gem_name, override: nil)
        raise Error, %(invalid gem name "#{gem_name}") unless GEM_FORMAT.match?(gem_name)

        @gem_name = gem_name
        @extension = override || derive(gem_name)
        self.class.check_name!("extension", @extension)
      end

      def module_name = self.class.camelize(extension)

      private

      def derive(gem_name)
        prefix = PREFIXES.find { |candidate| gem_name.start_with?(candidate) }
        (prefix ? gem_name.delete_prefix(prefix) : gem_name).tr("-", SEPARATOR)
      end
    end
  end
end
