# frozen_string_literal: true

module Boto
  class Operation
    # Raised by Result#value! on a failure. Keeps the Result so the caller can read the code and details.
    class FailedError < StandardError
      attr_reader :result

      def initialize(result)
        @result = result
        super(describe(result.failure))
      end

      private

      def describe(failure)
        failure.message ? "#{failure.code}: #{failure.message}" : failure.code.to_s
      end
    end
  end
end
