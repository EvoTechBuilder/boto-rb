# frozen_string_literal: true

module Boto
  # Param type for booleans. Accepts true/false and their string/"1"/"0" forms.
  module Boolean
    TRUE_VALUES = [true, "true", "1"].freeze
    FALSE_VALUES = [false, "false", "0"].freeze

    def self.coerce(value)
      return true if TRUE_VALUES.include?(value)
      return false if FALSE_VALUES.include?(value)

      raise ArgumentError, "must be a boolean"
    end
  end
end
