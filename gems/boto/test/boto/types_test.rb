# frozen_string_literal: true

require "test_helper"
require "date"
require "time"

module Boto
  class TypesTest < Minitest::Test
    class AddressSchema
      def self.coerce(value)
        raise Types::Invalid.new([{ path: "zip", message: "must be a String" }]) unless value[:zip].is_a?(String)

        value
      end

      def self.serialize(value)
        { "zip" => value[:zip] }
      end

      def self.json_schema_ref
        { "$ref" => "#/components/schemas/Address" }
      end
    end

    def errors_for(type, value, **options)
      error = assert_raises(Types::Invalid) { Types.build(type, **options).coerce(value) }
      error.errors.map { |item| [item[:path], item[:message]] }
    end

    def test_string_coerces_only_strings
      assert_equal "abc", Types.build(String).coerce("abc")
      assert_equal [["", "must be a String"]], errors_for(String, 1)
    end

    def test_integer_accepts_integers_and_digit_strings
      type = Types.build(Integer)
      assert_equal 42, type.coerce(42)
      assert_equal(-7, type.coerce("-7"))
      assert_equal [["", "must be an Integer"]], errors_for(Integer, "1.5")
      assert_equal [["", "must be an Integer"]], errors_for(Integer, "abc")
    end

    def test_float_coerces_numbers_and_numeric_strings
      type = Types.build(Float)
      assert_equal 1.0, type.coerce(1)
      assert_equal 2.5, type.coerce(2.5)
      assert_equal 2.5, type.coerce("2.5")
      assert_equal [["", "must be a Float"]], errors_for(Float, "abc")
    end

    def test_boolean_coerces_known_values
      type = Types.build(Boto::Boolean)
      assert_equal true, type.coerce("true")
      assert_equal false, type.coerce("0")
      assert_equal [["", "must be a boolean"]], errors_for(Boto::Boolean, "yes")
    end

    def test_date_accepts_date_and_iso_strings
      assert_equal Date.new(2026, 1, 2), Types.build(Date).coerce("2026-01-02")
      assert_equal Date.new(2026, 1, 2), Types.build(Date).coerce(Date.new(2026, 1, 2))
    end

    def test_date_rejects_invalid_calendar_dates_and_other_formats
      expected = [["", "must be a date (YYYY-MM-DD)"]]
      assert_equal expected, errors_for(Date, "2026-02-30")
      assert_equal expected, errors_for(Date, "02/01/2026")
    end

    def test_time_accepts_iso_strings_with_zone
      assert_equal Time.utc(2026, 1, 2, 10), Types.build(Time).coerce("2026-01-02T10:00:00Z")
      assert_equal Time.utc(2026, 1, 2, 7), Types.build(Time).coerce("2026-01-02T10:00:00+03:00")
    end

    def test_time_rejects_missing_zone
      expected = [["", "must be a date-time (ISO 8601 with time zone)"]]
      assert_equal expected, errors_for(Time, "2026-01-02T10:00:00")
      assert_equal expected, errors_for(Time, Time.now.to_s)
    end

    def test_min_and_max_on_integer
      assert_equal [["", "must be greater than or equal to 1"]], errors_for(Integer, 0, min: 1)
      assert_equal [["", "must be less than or equal to 100"]], errors_for(Integer, 101, max: 100)
      assert_equal 100, Types.build(Integer, min: 1, max: 100).coerce(100)
    end

    def test_min_and_max_on_float
      assert_equal [["", "must be greater than or equal to 0.5"]], errors_for(Float, 0.1, min: 0.5)
      assert_equal [["", "must be less than or equal to 2"]], errors_for(Float, "2.5", max: 2)
    end

    def test_min_and_max_on_string_use_length
      assert_equal [["", "must have at least 1 characters"]], errors_for(String, "", min: 1)
      assert_equal [["", "must have at most 3 characters"]], errors_for(String, "abcd", max: 3)
    end

    def test_enum_on_string
      type = Types.build(String, enum: %w[admin member])
      assert_equal "admin", type.coerce("admin")
      assert_equal [["", "must be one of: admin, member"]], errors_for(String, "owner", enum: %w[admin member])
    end

    def test_enum_on_integer_compares_coerced_values
      assert_equal 2, Types.build(Integer, enum: [1, 2]).coerce("2")
      assert_equal [["", "must be one of: 1, 2"]], errors_for(Integer, 3, enum: [1, 2])
    end

    def test_enum_on_date_uses_coerced_values
      assert_equal Date.new(2026, 1, 2), Types.build(Date, enum: ["2026-01-02"]).coerce("2026-01-02")
      assert_equal [["", "must be one of: 2026-01-02"]], errors_for(Date, "2026-01-03", enum: ["2026-01-02"])
    end

    def test_pattern_on_string
      type = Types.build(String, pattern: /\A[a-z]+\z/)
      assert_equal "abc", type.coerce("abc")
      assert_equal [["", "must match the pattern"]], errors_for(String, "ABC", pattern: /\A[a-z]+\z/)
    end

    def test_constraints_are_checked_after_coercion
      assert_equal [["", "must be an Integer"]], errors_for(Integer, "x", min: 1)
    end

    def test_min_on_boolean_raises_on_build
      assert_build_error("min and max are not supported for this type") { Types.build(Boto::Boolean, min: 1) }
    end

    def test_min_on_date_raises_on_build
      assert_build_error("min and max are not supported for this type") { Types.build(Date, max: 1) }
    end

    def test_non_numeric_min_raises_on_build
      assert_build_error("min and max must be Numeric") { Types.build(Integer, min: "1") }
    end

    def test_unanchored_pattern_raises_on_build
      assert_build_error("pattern must be anchored with \\A and \\z") { Types.build(String, pattern: /abc/) }
    end

    def test_pattern_on_non_string_raises_on_build
      assert_build_error("pattern is only supported for String") { Types.build(Integer, pattern: /\A\d+\z/) }
    end

    def test_enum_with_wrong_type_raises_on_build
      assert_build_error("enum values must match the type") { Types.build(Integer, enum: ["x"]) }
    end

    def test_empty_enum_raises_on_build
      assert_build_error("enum must be a non-empty Array") { Types.build(String, enum: []) }
    end

    def test_unsupported_type_raises_on_build
      error = assert_raises(ArgumentError) { Types.build(Hash) }
      assert_match(/unsupported type/, error.message)
    end

    def test_list_with_two_item_types_raises_on_build
      assert_build_error("list type must have exactly one item type") { Types.build([Integer, String]) }
    end

    def test_enum_and_pattern_on_list_raise_on_build
      assert_build_error("enum is not supported for lists") { Types.build([Integer], enum: [1]) }
      assert_build_error("pattern is not supported for lists") { Types.build([String], pattern: /\A\w\z/) }
    end

    def test_constraints_on_schema_raise_on_build
      assert_build_error("min is not supported for schema types") { Types.build(AddressSchema, min: 1) }
    end

    def test_list_coerces_each_item
      assert_equal [1, 2], Types.build([Integer]).coerce(["1", 2])
    end

    def test_list_rejects_non_array
      assert_equal [["", "must be an array"]], errors_for([Integer], "1")
    end

    def test_list_item_error_has_index_path
      assert_equal [["[1]", "must be an Integer"]], errors_for([Integer], [1, "x"])
    end

    def test_list_aggregates_all_item_errors
      expected = [["[0]", "must be an Integer"], ["[2]", "must be an Integer"]]
      assert_equal expected, errors_for([Integer], ["a", 2, "b"])
    end

    def test_nested_list_error_path
      assert_equal [["[0][1]", "must be an Integer"]], errors_for([[Integer]], [[1, "x"]])
    end

    def test_list_min_and_max_on_size
      assert_equal [["", "must have at least 1 items"]], errors_for([Integer], [], min: 1)
      assert_equal [["", "must have at most 2 items"]], errors_for([Integer], [1, 2, 3], max: 2)
      assert_equal [1, 2], Types.build([Integer], min: 1, max: 2).coerce([1, 2])
    end

    def test_schema_coerces_through_the_schema
      assert_equal({ zip: "123" }, Types.build(AddressSchema).coerce({ zip: "123" }))
      assert_equal [["zip", "must be a String"]], errors_for(AddressSchema, { zip: 1 })
    end

    def test_schema_error_inside_list_gets_index_path
      assert_equal [["[0].zip", "must be a String"]], errors_for([AddressSchema], [{ zip: 1 }])
    end

    def test_dump_date
      assert_equal "2026-01-02", Types.build(Date).dump(Date.new(2026, 1, 2))
    end

    def test_dump_time_keeps_milliseconds
      time = Time.utc(2026, 1, 2, 10, 0, Rational(123, 1000))
      assert_equal "2026-01-02T10:00:00.123Z", Types.build(Time).dump(time)
    end

    def test_dump_list_maps_items
      assert_equal ["2026-01-02"], Types.build([Date]).dump([Date.new(2026, 1, 2)])
    end

    def test_dump_schema_uses_serialize
      assert_equal({ "zip" => "123" }, Types.build(AddressSchema).dump({ zip: "123" }))
    end

    def test_dump_scalars_return_the_value
      assert_equal 3, Types.build(Integer).dump(3)
      assert_equal true, Types.build(Boto::Boolean).dump(true)
    end

    def test_json_schema_string_with_restrictions
      schema = Types.build(String, min: 1, max: 10, enum: %w[a b]).json_schema
      assert_equal({ "type" => "string", "minLength" => 1, "maxLength" => 10, "enum" => %w[a b] }, schema)
    end

    def test_json_schema_pattern_is_converted_to_caret_and_dollar
      schema = Types.build(String, pattern: /\A[a-z]+\z/).json_schema
      assert_equal({ "type" => "string", "pattern" => "^[a-z]+$" }, schema)
    end

    def test_json_schema_integer_and_float
      assert_equal({ "type" => "integer", "minimum" => 1, "maximum" => 100 },
                   Types.build(Integer, min: 1, max: 100).json_schema)
      assert_equal({ "type" => "number", "enum" => [1.5] }, Types.build(Float, enum: [1.5]).json_schema)
    end

    def test_json_schema_boolean_date_and_time
      assert_equal({ "type" => "boolean" }, Types.build(Boto::Boolean).json_schema)
      assert_equal({ "type" => "string", "format" => "date" }, Types.build(Date).json_schema)
      assert_equal({ "type" => "string", "format" => "date-time" }, Types.build(Time).json_schema)
    end

    def test_json_schema_date_enum_uses_dumped_values
      schema = Types.build(Date, enum: ["2026-01-02"]).json_schema
      assert_equal ["2026-01-02"], schema["enum"]
    end

    def test_json_schema_list_with_item_bounds
      schema = Types.build([Integer], min: 1, max: 10).json_schema
      assert_equal({ "type" => "array", "items" => { "type" => "integer" }, "minItems" => 1, "maxItems" => 10 }, schema)
    end

    def test_json_schema_schema_uses_ref
      assert_equal({ "$ref" => "#/components/schemas/Address" }, Types.build(AddressSchema).json_schema)
    end

    def test_json_schema_is_deeply_frozen
      schema = Types.build([String], enum: nil, min: 1).json_schema
      assert schema.frozen?
      assert schema["items"].frozen?
      enum_schema = Types.build([Integer]).json_schema
      assert enum_schema["items"].frozen?

      scalar = Types.build(String, enum: %w[a b]).json_schema
      assert scalar.frozen?
      assert scalar["enum"].frozen?
    end

    def test_built_types_are_frozen
      assert Types.build(Integer).frozen?
      assert Types.build([Integer]).frozen?
      assert Types.build(AddressSchema).frozen?
    end

    def test_schema_json_schema_ref_is_not_frozen_on_caller_object
      ref = { "$ref" => "x" }
      schema_class = Class.new(AddressSchema) { define_singleton_method(:json_schema_ref) { ref } }
      Types.build(schema_class)
      refute ref.frozen?
    end

    def test_messages_never_contain_the_received_value
      secret = "SEGREDO"
      assert_no_secret(Integer, secret)
      assert_no_secret(Float, secret)
      assert_no_secret(Date, secret)
      assert_no_secret(Time, secret)
      assert_no_secret(Boto::Boolean, secret)
      assert_no_secret([Integer], [secret])
      assert_no_secret(Integer, secret, min: 1)
      assert_no_secret(String, secret, enum: %w[a b])
      assert_no_secret(String, secret, pattern: /\A[a-z]+\z/)
    end

    def test_join_path_examples
      assert_equal "address.zip", Types.join_path("address", "zip")
      assert_equal "tags[2]", Types.join_path("tags", "[2]")
      assert_equal "[2].name", Types.join_path("[2]", "name")
      assert_equal "x", Types.join_path("x", "")
      assert_equal "zip", Types.join_path("", "zip")
    end

    def test_invalid_message_joins_errors
      error = Types::Invalid.new([{ path: "a", message: "x" }, { path: "", message: "y" }])
      assert_equal "a: x; y", error.message
      assert_equal 2, error.errors.size
    end

    def test_invalid_single_uses_empty_path
      error = Types::Invalid.single("must be a String")
      assert_equal "must be a String", error.message
      assert_equal [{ path: "", message: "must be a String" }], error.errors
    end

    def test_coerce_happy_path_allocates_nothing
      type = Types.build(Integer, min: 1)
      50.times { type.coerce("42") }

      # The first execution of each measuring line allocates one object of the harness itself,
      # so the same window runs twice and only the second (steady state) is asserted.
      windows = Array.new(2) do
        before = GC.stat(:total_allocated_objects)
        type.coerce("42")
        after = GC.stat(:total_allocated_objects)
        after - before
      end

      assert_equal 0, windows.last
    end

    private

    def assert_build_error(message)
      error = assert_raises(ArgumentError) { yield }
      assert_equal message, error.message
    end

    def assert_no_secret(type, value, **options)
      error = assert_raises(Types::Invalid) { Types.build(type, **options).coerce(value) }
      refute_includes error.message, "SEGREDO"
    end
  end
end
