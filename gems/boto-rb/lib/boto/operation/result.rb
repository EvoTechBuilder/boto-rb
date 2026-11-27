# frozen_string_literal: true

module Boto
  class Operation
    # What an operation returns: a value on success, or a Failure. Immutable.
    class Result < Data.define(:value, :failure)
      def self.success(value = nil) = new(value: value, failure: nil)

      def self.failure(code, message = nil, **details)
        new(value: nil, failure: Failure.new(code:, message:, details:))
      end

      def success? = failure.nil?

      def failure? = !success?

      def value!
        return value if success?

        raise FailedError.new(self)
      end
    end
  end
end
