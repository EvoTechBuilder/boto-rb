# frozen_string_literal: true

require "test_helper"

class Boto::CLI::FieldSpecTest < Minitest::Test
  NAMESPACE = "Catalogo"

  def test_maps_primitive_types
    {
      "string" => "String",
      "integer" => "Integer",
      "float" => "Float",
      "boolean" => "Boto::Boolean",
      "date" => "Date",
      "time" => "Time"
    }.each do |type, expected|
      assert_equal expected, parse("field:#{type}").type_source, type
    end
  end

  def test_maps_list_of_primitive
    assert_equal "[String]", parse("tags:[string]").type_source
  end

  def test_maps_name_to_project_schema
    assert_equal "Catalogo::CategorySchema", parse("category:category").type_source
  end

  def test_maps_underscored_name_to_camel_schema
    assert_equal "Catalogo::LineItemSchema", parse("item:line_item").type_source
  end

  def test_does_not_duplicate_schema_suffix
    assert_equal "Catalogo::ProductSchema", parse("item:product_schema").type_source
  end

  def test_maps_list_of_project_schema
    assert_equal "[Catalogo::CategorySchema]", parse("categories:[category]").type_source
  end

  def test_fields_are_required_by_default
    assert parse("price:float").required
  end

  def test_trailing_question_mark_makes_field_optional
    field = parse("available_on:date?")

    assert_equal "Date", field.type_source
    refute field.required
  end

  def test_trailing_question_mark_works_on_lists
    field = parse("tags:[string]?")

    assert_equal "[String]", field.type_source
    refute field.required
  end

  def test_declaration_for_required_field
    assert_equal "field :price, Float", parse("price:float").declaration
  end

  def test_declaration_for_optional_field
    assert_equal "field :available_on, Date, required: false", parse("available_on:date?").declaration
  end

  def test_instances_are_immutable
    assert_predicate parse("price:float"), :frozen?
  end

  def test_rejects_spec_without_type
    assert_invalid "price"
  end

  def test_rejects_spec_with_empty_type
    assert_invalid "price:"
  end

  def test_rejects_spec_with_empty_name
    assert_invalid ":float"
  end

  def test_rejects_invalid_name
    assert_invalid "Price:float"
    assert_invalid "price name:float"
  end

  def test_rejects_list_of_list
    assert_invalid "matrix:[[string]]"
  end

  def test_rejects_empty_list
    assert_invalid "tags:[]"
  end

  def test_rejects_extra_colon
    assert_invalid "price:float:int"
  end

  def test_rejects_double_optional_marker
    assert_invalid "price:float??"
  end

  def test_rejects_invalid_type_name
    assert_invalid "price:Float"
  end

  private

  def parse(spec) = Boto::CLI::FieldSpec.parse(spec, namespace: NAMESPACE)

  def assert_invalid(spec)
    error = assert_raises(Boto::CLI::Error) { parse(spec) }
    assert_includes error.message, %("#{spec}")
  end
end
