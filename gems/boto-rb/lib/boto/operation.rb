# frozen_string_literal: true

module Boto
  # Base class of operations (business rules). Call it with .call; it always returns a Result.
  class Operation
    include ProjectApp

    def self.call(...)
      returned = new(...).call
      returned.is_a?(Result) ? returned : Result.success(returned)
    end
    private_class_method :new

    def initialize(input = nil)
      @input = input
    end

    def call
      raise NotImplementedError, "#{self.class}#call"
    end

    private

    attr_reader :input

    def success(value = nil) = Result.success(value)
    def failure(code, message = nil, **details) = Result.failure(code, message, **details)
  end
end
