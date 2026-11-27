# frozen_string_literal: true

require "test_helper"

module OperationTestOps
  class Identity < Boto::Operation
    def call = input
  end

  class Succeed < Boto::Operation
    def call = success(input)
  end

  class Fail < Boto::Operation
    def call = failure(:conflict, "taken", a: 1)
  end

  class ReturnsNil < Boto::Operation
    def call = nil
  end

  class ReturnsFalse < Boto::Operation
    def call = false
  end

  class WithInit < Boto::Operation
    def initialize(input, repo:)
      super(input)
      @repo = repo
    end

    def call = [input, @repo]
  end

  class NoCall < Boto::Operation; end

  class Boom < Boto::Operation
    def call = raise("boom")
  end

  class Counter < Boto::Operation
    def call = (@calls = (@calls || 0) + 1)
  end
end

module Boto
  class OperationTest < Minitest::Test
    def test_success_result_passes_through
      result = OperationTestOps::Succeed.call(1)

      assert_predicate result, :success?
      assert_equal 1, result.value
    end

    def test_failure_result_passes_through
      failure = OperationTestOps::Fail.call.failure

      assert_equal :conflict, failure.code
      assert_equal "taken", failure.message
      assert_equal({ a: 1 }, failure.details)
    end

    def test_plain_return_value_becomes_success
      assert_equal 1, OperationTestOps::Identity.call(1).value
    end

    def test_nil_and_false_become_success_with_that_value
      nil_result = OperationTestOps::ReturnsNil.call
      false_result = OperationTestOps::ReturnsFalse.call

      assert_predicate nil_result, :success?
      assert_nil nil_result.value
      assert_predicate false_result, :success?
      assert_equal false, false_result.value
    end

    def test_positional_and_keyword_reach_initialize
      assert_equal [7, :repo], OperationTestOps::WithInit.call(7, repo: :repo).value
    end

    def test_input_is_nil_without_arguments
      assert_nil OperationTestOps::Identity.call.value
    end

    def test_result_from_call_is_returned_as_is
      shared = Boto::Operation::Result.success(:shared)

      assert_same shared, OperationTestOps::Identity.call(shared)
    end

    def test_new_is_private
      assert_raises(NoMethodError) { OperationTestOps::Identity.new(1) }
    end

    def test_new_is_private_on_subclasses_of_subclasses
      assert_raises(NoMethodError) { OperationTestOps::WithInit.new(1, repo: nil) }
    end

    def test_missing_call_raises_not_implemented_with_class_name
      error = assert_raises(NotImplementedError) { OperationTestOps::NoCall.call }

      assert_includes error.message, "OperationTestOps::NoCall#call"
    end

    def test_exception_inside_call_is_not_captured
      error = assert_raises(RuntimeError) { OperationTestOps::Boom.call }

      assert_equal "boom", error.message
    end

    def test_extra_arguments_without_initialize_raise_argument_error
      assert_raises(ArgumentError) { OperationTestOps::Identity.call(1, 2) }
      assert_raises(ArgumentError) { OperationTestOps::Identity.call(1, x: 2) }
    end

    def test_each_call_gets_a_new_instance
      assert_equal 1, OperationTestOps::Counter.call.value
      assert_equal 1, OperationTestOps::Counter.call.value
    end
  end
end
