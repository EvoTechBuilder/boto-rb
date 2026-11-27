# frozen_string_literal: true

module Boto
  class Operation
    # Why an operation failed: a Symbol code for the caller to branch on, plus a message and extra details.
    class Failure < Data.define(:code, :message, :details)
      def initialize(code:, message: nil, details: {})
        raise ArgumentError, "failure code must be a Symbol, got #{code.inspect}" unless code.is_a?(Symbol)

        # dup: freezing the caller's own hash would be a surprising side effect.
        super(code:, message:, details: details.dup.freeze)
      end
    end
  end
end
