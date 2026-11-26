# frozen_string_literal: true

require "openssl"
require "rack/utils"

module Boto
  module Security
    # Helpers shared by the security plugins to read secrets and compare them safely.
    module Secrets
      # Secrets may be given as lambdas so they stay out of the code; they are read once, at boot.
      def self.resolve(value)
        value.respond_to?(:call) ? value.call : value
      end

      # Hashing both sides first gives equal-length inputs, so the comparison leaks neither content nor length.
      def self.equal?(given, expected)
        return false if given.nil? || expected.nil?

        Rack::Utils.secure_compare(digest(given), digest(expected))
      end

      # Strategies keep their own frozen copy, so mutating the caller's objects later changes nothing.
      def self.frozen_copy(value)
        case value
        when String then value.dup.freeze
        when Array then value.map { frozen_copy(_1) }.freeze
        when Hash then value.to_h { |key, item| [frozen_copy(key), frozen_copy(item)] }.freeze
        else value
        end
      end

      def self.digest(value)
        OpenSSL::Digest::SHA256.digest(value.to_s)
      end
      private_class_method :digest
    end
  end
end
