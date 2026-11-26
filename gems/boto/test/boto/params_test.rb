# frozen_string_literal: true

require "test_helper"

module Boto
  class ParamsTest < Minitest::Test
    NO_INPUT = {}.freeze

    def call(params, path: NO_INPUT, query: NO_INPUT, body: NO_INPUT)
      params.call(path: path, query: query, body: body)
    end

    def unprocessable_errors(params, path: NO_INPUT, query: NO_INPUT, body: NO_INPUT)
      error = assert_raises(Boto::Error::Unprocessable) { call(params, path: path, query: query, body: body) }
      assert_equal 422, error.status
      error.errors
    end

    def test_string_accepts_only_strings
      params = Params.new.declare(:name, String)
      assert_equal({ name: "ana" }, call(params, query: { "name" => "ana" }))
      assert_equal [{ param: "name", message: "must be a String" }],
                   unprocessable_errors(params, query: { "name" => 1 })
    end

    def test_integer_accepts_integers_and_decimal_strings
      params = Params.new.declare(:count, Integer)
      assert_equal({ count: 7 }, call(params, query: { "count" => 7 }))
      assert_equal({ count: 42 }, call(params, query: { "count" => "42" }))
      assert_equal({ count: -3 }, call(params, query: { "count" => "-3" }))
    end

    def test_integer_rejects_non_integer_values
      params = Params.new.declare(:count, Integer)
      ["4.2", "1e3", " 1", ""].each do |value|
        errors = unprocessable_errors(params, query: { "count" => value })
        assert_equal [{ param: "count", message: "must be an Integer" }], errors
      end
      assert_equal "must be an Integer", unprocessable_errors(params, body: { "count" => 1.5 }).first[:message]
    end

    def test_float_accepts_numbers_and_strings
      params = Params.new.declare(:price, Float)
      assert_equal({ price: 1.0 }, call(params, body: { "price" => 1 }))
      assert_equal({ price: 2.5 }, call(params, body: { "price" => 2.5 }))
      assert_equal({ price: 3.5 }, call(params, query: { "price" => "3.5" }))
    end

    def test_float_rejects_invalid_values
      params = Params.new.declare(:price, Float)
      assert_equal [{ param: "price", message: "must be a Float" }],
                   unprocessable_errors(params, query: { "price" => "abc" })
      assert_equal "must be a Float", unprocessable_errors(params, body: { "price" => true }).first[:message]
    end

    def test_boolean_accepts_known_values
      params = Params.new.declare(:active, Boolean)
      assert_equal({ active: true }, call(params, query: { "active" => "true" }))
      assert_equal({ active: false }, call(params, body: { "active" => false }))
    end

    def test_boolean_rejects_unknown_values
      params = Params.new.declare(:active, Boolean)
      assert_equal "must be a boolean", unprocessable_errors(params, query: { "active" => "yes" }).first[:message]
    end

    def test_path_takes_precedence_over_query_and_body
      params = Params.new.declare(:id, Integer)
      result = call(params, path: { id: 1 }, query: { "id" => "2" }, body: { "id" => 3 })
      assert_equal({ id: 1 }, result)
    end

    def test_query_takes_precedence_over_body
      params = Params.new.declare(:name, String)
      result = call(params, query: { "name" => "from query" }, body: { "name" => "from body" })
      assert_equal({ name: "from query" }, result)
    end

    def test_default_is_used_when_value_is_absent
      params = Params.new.declare(:page, Integer, default: 1)
      assert_equal({ page: 1 }, call(params))
    end

    def test_default_is_not_coerced_and_skips_required
      params = Params.new.declare(:page, Integer, default: 1, required: true)
      assert_equal({ page: 1 }, call(params))
    end

    def test_optional_absent_param_is_nil
      params = Params.new.declare(:note, String, required: false)
      assert_equal({ note: nil }, call(params))
    end

    def test_absent_required_param_is_unprocessable
      params = Params.new.declare(:name, String)
      assert_equal [{ param: "name", message: "is required" }], unprocessable_errors(params)
    end

    def test_nil_in_body_counts_as_absent
      params = Params.new.declare(:name, String)
      assert_equal [{ param: "name", message: "is required" }],
                   unprocessable_errors(params, body: { "name" => nil })
    end

    def test_false_in_body_is_a_present_value
      params = Params.new.declare(:active, Boolean, default: true)
      assert_equal({ active: false }, call(params, body: { "active" => false }))
    end

    def test_aggregates_errors_from_all_params
      params = Params.new.declare(:name, String).declare(:count, Integer)
      errors = unprocessable_errors(params, body: { "name" => 1 })
      assert_equal [{ param: "name", message: "must be a String" }, { param: "count", message: "is required" }],
                   errors
    end

    def test_undeclared_params_are_ignored
      params = Params.new.declare(:name, String)
      result = call(params, body: { "name" => "ana", "other" => 1 })
      assert_equal({ name: "ana" }, result)
    end

    def test_unsupported_type_raises_argument_error
      error = assert_raises(ArgumentError) { Params.new.declare(:tags, Array) }
      assert_match "unsupported param type", error.message
    end

    def test_duplicate_name_raises_argument_error
      params = Params.new.declare(:name, String)
      error = assert_raises(ArgumentError) { params.declare(:name, Integer) }
      assert_match "duplicate param name", error.message
    end

    def test_declare_returns_self_and_names_lists_symbols
      params = Params.new
      assert_same params, params.declare(:name, String).declare("count", Integer)
      assert_equal [:name, :count], params.names
    end

    def test_frozen_params_reject_new_declarations
      params = Params.new.declare(:name, String).freeze
      assert_predicate params, :frozen?
      assert_raises(FrozenError) { params.declare(:count, Integer) }
    end

    def test_without_declarations_returns_shared_empty_hash
      assert_same Params::EMPTY, call(Params.new, body: { "name" => "ana" })
    end
  end
end
