# frozen_string_literal: true

require "test_helper"

module Boto
  class Operation
    class ResultTest < Minitest::Test
      def test_success_predicates
        result = Result.success(1)

        assert_predicate result, :success?
        refute_predicate result, :failure?
        assert_nil result.failure
      end

      def test_failure_predicates
        result = Result.failure(:conflict)

        refute_predicate result, :success?
        assert_predicate result, :failure?
        assert_nil result.value
      end

      def test_value_bang_returns_value_on_success
        assert_equal 1, Result.success(1).value!
      end

      def test_value_bang_raises_failed_error_on_failure
        result = Result.failure(:conflict, "taken")
        error = assert_raises(FailedError) { result.value! }

        assert_same result, error.result
        assert_equal "conflict: taken", error.message
      end

      def test_failed_error_message_without_message_is_only_the_code
        error = assert_raises(FailedError) { Result.failure(:not_found).value! }

        assert_equal "not_found", error.message
      end

      def test_pattern_matching_on_success
        matched = case Result.success(5)
                  in { failure: nil, value: } then value
                  end

        assert_equal 5, matched
      end

      def test_pattern_matching_on_failure_code
        matched = case Result.failure(:conflict, "taken")
                  in { failure: { code: :conflict } } then :matched
                  end

        assert_equal :matched, matched
      end

      def test_pattern_matching_does_not_match_other_code
        assert_raises(NoMatchingPatternError) do
          case Result.failure(:forbidden)
          in { failure: { code: :conflict } } then nil
          end
        end
      end

      def test_result_is_frozen
        assert_predicate Result.success(1), :frozen?
        assert_predicate Result.failure(:conflict), :frozen?
      end

      def test_details_are_frozen_with_empty_default
        details = Result.failure(:conflict).failure.details

        assert_equal({}, details)
        assert_predicate details, :frozen?
      end

      def test_details_are_frozen_and_copied_from_keywords
        details = { a: 1 }
        failure = Result.failure(:conflict, nil, **details).failure

        assert_equal({ a: 1 }, failure.details)
        assert_predicate failure.details, :frozen?
        refute_same details, failure.details
      end

      def test_non_symbol_code_raises_argument_error
        error = assert_raises(ArgumentError) { Result.failure("conflict") }

        assert_equal 'failure code must be a Symbol, got "conflict"', error.message
      end
    end
  end
end
