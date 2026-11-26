# frozen_string_literal: true

require "test_helper"
require "date"
require "time"

module SchemaTestShop
  class AddressSchema < Boto::Schema
    field :street, String, max: 200
    field :zip, String, pattern: /\A\d{5}-?\d{3}\z/
  end

  class UserSchema < Boto::Schema
    field :id, Integer
    field :name, String, min: 1, max: 100
    field :email, String, required: false
    field :tags, [String], max: 10
    field :address, AddressSchema, required: false
  end

  class CustomerSchema < Boto::Schema
    field :addresses, [AddressSchema]
  end

  class EventSchema < Boto::Schema
    field :on, Date
    field :at, Time
  end

  class PointSchema < Boto::Schema
    field :x, Integer
    field :y, Integer
    field :label, String
  end

  module Admin
    class RoleSchema < Boto::Schema
      field :code, String
    end
  end

  Point = Struct.new(:x, :y, :label)
  Account = Struct.new(:id, :name, :email, :tags, :address, :password_hash)
end

class SchemaTestPlainSchema < Boto::Schema
  field :code, String
end

module Boto
  class SchemaTest < Minitest::Test
    WARMUP_RUNS = 50
    ALLOCATION_WINDOWS = 2

    def coerce_errors(schema, input)
      error = assert_raises(Types::Invalid) { schema.coerce(input) }
      error.errors.map { |item| [item[:path], item[:message]] }
    end

    def allocations
      before = GC.stat(:total_allocated_objects)
      yield
      GC.stat(:total_allocated_objects) - before
    end

    # The first run of a measured line allocates a harness object, so the window is repeated and the last run is kept.
    def measure_allocations(&block)
      WARMUP_RUNS.times(&block)
      Array.new(ALLOCATION_WINDOWS) { allocations(&block) }.last
    end

    def test_coerce_accepts_string_keys_and_converts_types
      user = SchemaTestShop::UserSchema.coerce("id" => "7", "name" => "Ana", "tags" => [])

      assert_equal 7, user.id
      assert_equal "Ana", user.name
      assert_equal({ id: 7, name: "Ana", email: nil, tags: [], address: nil }, user.to_h)
    end

    def test_coerce_accepts_symbol_keys
      user = SchemaTestShop::UserSchema.coerce(id: 7, name: "Ana", tags: ["a"])

      assert_equal({ id: 7, name: "Ana", email: nil, tags: ["a"], address: nil }, user.to_h)
    end

    def test_coerce_ignores_extra_fields
      user = SchemaTestShop::UserSchema.coerce("id" => 1, "name" => "a", "tags" => [], "extra" => 1)

      refute_respond_to user, :extra
      assert_equal %i[id name email tags address], user.to_h.keys
    end

    def test_coerce_returns_frozen_instance_with_readers
      user = SchemaTestShop::UserSchema.coerce("id" => 1, "name" => "a", "tags" => ["x"])

      assert_predicate user, :frozen?
      assert_equal ["x"], user.tags
    end

    def test_coerce_builds_nested_schema_and_to_h_converts_it
      user = SchemaTestShop::UserSchema.coerce(
        "id" => 1, "name" => "a", "tags" => [],
        "address" => { "street" => "Rua", "zip" => "12345-678" }
      )

      assert_instance_of SchemaTestShop::AddressSchema, user.address
      assert_equal({ street: "Rua", zip: "12345-678" }, user.to_h[:address])
    end

    def test_optional_absent_or_null_is_nil
      user = SchemaTestShop::UserSchema.coerce("id" => 1, "name" => "a", "tags" => [], "email" => nil)

      assert_nil user.email
      assert_nil user.address
    end

    def test_missing_required_field_reports_its_path
      assert_equal [["id", "is required"]], coerce_errors(SchemaTestShop::UserSchema, "name" => "a", "tags" => [])
    end

    def test_null_required_field_is_reported
      assert_equal [["id", "is required"]], coerce_errors(SchemaTestShop::UserSchema, "id" => nil, "name" => "a", "tags" => [])
    end

    def test_errors_are_aggregated_with_nested_and_list_paths
      input = {
        "id" => "x", "name" => "", "tags" => ["a", "b", 3],
        "address" => { "street" => "s", "zip" => "nope" }
      }

      assert_equal [
        ["id", "must be an Integer"],
        ["name", "must have at least 1 characters"],
        ["tags[2]", "must be a String"],
        ["address.zip", "must match the pattern"]
      ], coerce_errors(SchemaTestShop::UserSchema, input)
    end

    def test_list_of_schemas_reports_index_and_nested_path
      input = {
        "addresses" => [
          { "street" => "a", "zip" => "12345-678" },
          { "street" => "b", "zip" => "bad" }
        ]
      }

      assert_equal [["addresses[1].zip", "must match the pattern"]],
                   coerce_errors(SchemaTestShop::CustomerSchema, input)
    end

    def test_non_hash_input_is_rejected
      assert_equal [["", "must be an object"]], coerce_errors(SchemaTestShop::UserSchema, nil)
      assert_equal [["", "must be an object"]], coerce_errors(SchemaTestShop::UserSchema, [1])
    end

    def test_serialize_hash_with_symbol_and_string_keys
      expected = { id: 7, name: "Ana", email: nil, tags: ["a"], address: nil }

      assert_equal expected, SchemaTestShop::UserSchema.serialize(id: 7, name: "Ana", tags: ["a"])
      assert_equal expected, SchemaTestShop::UserSchema.serialize("id" => 7, "name" => "Ana", "tags" => ["a"], "email" => nil)
    end

    def test_serialize_object_outputs_only_declared_fields
      account = SchemaTestShop::Account.new(7, "Ana", nil, [], nil, "secret-hash")

      result = SchemaTestShop::UserSchema.serialize(account)

      assert_equal({ id: 7, name: "Ana", email: nil, tags: [], address: nil }, result)
      refute_includes result.to_s, "secret-hash"
    end

    def test_serialize_schema_instance
      user = SchemaTestShop::UserSchema.coerce("id" => 1, "name" => "a", "tags" => [], "address" => { "street" => "s", "zip" => "12345-678" })

      assert_equal user.to_h, SchemaTestShop::UserSchema.serialize(user)
    end

    def test_serialize_nested_hash
      result = SchemaTestShop::UserSchema.serialize(
        id: 1, name: "a", tags: [], address: { street: "Rua", zip: "12345-678" }
      )

      assert_equal({ street: "Rua", zip: "12345-678" }, result[:address])
    end

    def test_serialize_list_of_nested_schemas_mixing_hashes_and_instances
      address = SchemaTestShop::AddressSchema.coerce("street" => "b", "zip" => "22222-333")
      result = SchemaTestShop::CustomerSchema.serialize(
        addresses: [{ street: "a", zip: "12345-678" }, address]
      )

      assert_equal [{ street: "a", zip: "12345-678" }, { street: "b", zip: "22222-333" }], result[:addresses]
    end

    def test_serialize_formats_date_and_time_as_iso8601
      result = SchemaTestShop::EventSchema.serialize(on: Date.new(2026, 1, 2), at: Time.utc(2026, 1, 2, 3, 4, 5))

      assert_equal({ on: "2026-01-02", at: "2026-01-02T03:04:05.000Z" }, result)
    end

    def test_required_nil_on_output_raises_with_field_name
      error = assert_raises(Schema::OutputError) do
        SchemaTestShop::PointSchema.serialize(x: nil, y: 1, label: "a")
      end

      assert_equal "PointSchema.x is required", error.message
    end

    def test_json_schema_lists_properties_and_required
      schema = SchemaTestShop::UserSchema.json_schema

      assert_equal "object", schema["type"]
      assert_equal %w[id name email tags address], schema["properties"].keys
      assert_equal({ "type" => "integer" }, schema["properties"]["id"])
      assert_equal({ "type" => "string", "minLength" => 1, "maxLength" => 100 }, schema["properties"]["name"])
      assert_equal({ "type" => "array", "items" => { "type" => "string" }, "maxItems" => 10 }, schema["properties"]["tags"])
      assert_equal({ "$ref" => "#/components/schemas/AddressSchema" }, schema["properties"]["address"])
      assert_equal %w[id name tags], schema["required"]
      assert_predicate schema, :frozen?
    end

    def test_json_schema_omits_required_when_empty
      klass = Class.new(Boto::Schema) { field :note, String, required: false }

      refute klass.json_schema.key?("required")
    end

    def test_json_schema_ref_points_to_schema_name
      ref = SchemaTestShop::UserSchema.json_schema_ref

      assert_equal({ "$ref" => "#/components/schemas/UserSchema" }, ref)
      assert_predicate ref, :frozen?
    end

    def test_schema_name_drops_first_namespace_segment
      assert_equal "UserSchema", SchemaTestShop::UserSchema.schema_name
      assert_equal "AdminRoleSchema", SchemaTestShop::Admin::RoleSchema.schema_name
      assert_equal "SchemaTestPlainSchema", SchemaTestPlainSchema.schema_name
    end

    def test_invalid_field_names_raise
      %i[Name na-me 1x class].each do |bad|
        assert_raises(ArgumentError) { Class.new(Boto::Schema) { field bad, String } }
      end
    end

    def test_duplicate_field_raises
      error = assert_raises(ArgumentError) do
        Class.new(Boto::Schema) do
          field :a, String
          field :a, Integer
        end
      end

      assert_match(/duplicate/, error.message)
    end

    def test_field_after_compile_raises
      klass = Class.new(Boto::Schema) { field :a, String }
      klass.compile!

      assert_raises(FrozenError) { klass.field :b, String }
    end

    def test_fields_are_owned_by_each_class
      klass = Class.new(Boto::Schema) { field :a, String }

      assert_equal [:a], klass.fields.map(&:name)
      assert_empty Class.new(Boto::Schema).fields
    end

    def test_compile_is_idempotent
      klass = Class.new(Boto::Schema) { field :a, String }

      assert_same klass, klass.compile!
      assert_same klass, klass.compile!
      assert_predicate klass, :compiled?
    end

    def test_compile_compiles_nested_schemas_inside_lists
      inner = Class.new(Boto::Schema) { field :value, Integer }
      outer = Class.new(Boto::Schema) { field :items, [[inner]] }

      outer.compile!

      assert_predicate inner, :compiled?
    end

    def test_coerce_works_without_explicit_compile
      klass = Class.new(Boto::Schema) { field :code, String }
      refute_predicate klass, :compiled?

      assert_equal "x", klass.coerce("code" => "x").code
      assert_predicate klass, :compiled?
    end

    def test_generated_helpers_are_private
      refute_respond_to SchemaTestShop::UserSchema, :__boto_coerce_field
      refute_respond_to SchemaTestShop::UserSchema, :__boto_serialize_hash
    end

    def test_types_build_accepts_schema_class
      type = Types.build(SchemaTestShop::AddressSchema)

      assert_equal({ "$ref" => "#/components/schemas/AddressSchema" }, type.json_schema)
      assert_equal "12345-678", type.coerce("street" => "s", "zip" => "12345-678").zip
    end

    def test_instances_compare_by_class_and_value
      first = SchemaTestShop::PointSchema.coerce("x" => 1, "y" => 2, "label" => "a")
      second = SchemaTestShop::PointSchema.coerce("x" => 1, "y" => 2, "label" => "a")

      assert_equal first, second
      assert_equal first.hash, second.hash
      assert_equal '#<PointSchema x=1 y=2 label="a">', first.inspect
    end

    def test_serialize_hash_allocates_only_the_output_hash
      point = SchemaTestShop::Point.new(1, 2, "a")

      count = measure_allocations { SchemaTestShop::PointSchema.serialize(point) }

      assert_operator count, :<=, 1
    end

    def test_coerce_allocates_only_the_instance
      input = { "x" => 1, "y" => 2, "label" => "a" }

      count = measure_allocations { SchemaTestShop::PointSchema.coerce(input) }

      assert_operator count, :<=, 1
    end
  end
end

class Boto::SchemaCycleTest < Minitest::Test
  module Tree
    class NodeSchema < Boto::Schema
      field :name, String
      field :children, [NodeSchema], required: false
    end
  end

  def test_self_referencing_schema_compiles_and_coerces
    node = Tree::NodeSchema.coerce({ "name" => "root", "children" => [{ "name" => "leaf" }] })
    assert_equal "leaf", node.children.first.name
    assert_equal({ name: "root", children: [{ name: "leaf", children: nil }] }, Tree::NodeSchema.serialize(node))
  end
end
