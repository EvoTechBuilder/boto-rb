# frozen_string_literal: true

require "test_helper"

module Boto
  class BooleanTest < Minitest::Test
    def test_truthy_values_coerce_to_true
      [true, "true", "1"].each { |value| assert_equal true, Boolean.coerce(value) }
    end

    def test_falsy_values_coerce_to_false
      [false, "false", "0"].each { |value| assert_equal false, Boolean.coerce(value) }
    end

    def test_invalid_values_raise_argument_error
      ["yes", nil, 2].each do |value|
        error = assert_raises(ArgumentError) { Boolean.coerce(value) }
        assert_equal "must be a boolean", error.message
      end
    end
  end
end
