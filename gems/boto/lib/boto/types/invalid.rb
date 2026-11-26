# frozen_string_literal: true

module Boto
  module Types
    # Raised when a value does not match its type. Each error is { path:, message: }.
    class Invalid < StandardError
      SEPARATOR = "; "

      attr_reader :errors

      def self.single(message)
        new([{ path: "", message: }])
      end

      def initialize(errors)
        @errors = errors.freeze
        super(errors.map { |error| format_error(error) }.join(SEPARATOR))
      end

      private

      def format_error(error)
        error[:path].empty? ? error[:message] : "#{error[:path]}: #{error[:message]}"
      end
    end
  end
end
