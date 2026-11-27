# frozen_string_literal: true

require "test_helper"

class Boto::CLI::ConstantNameTest < Minitest::Test
  NAMESPACE = "Catalogo"

  def test_name_with_folder
    name = build("products/show")

    assert_equal %w[products show], name.segments
    assert_equal "products/show", name.relative_path
    assert_equal "Show", name.class_name
    assert_equal %w[Catalogo Products], name.modules
    assert_equal "Catalogo::Products::Show", name.constant
  end

  def test_name_without_folder
    name = build("product")

    assert_equal %w[product], name.segments
    assert_equal "product", name.relative_path
    assert_equal "Product", name.class_name
    assert_equal %w[Catalogo], name.modules
    assert_equal "Catalogo::Product", name.constant
  end

  def test_underscore_becomes_camel_case
    assert_equal "Catalogo::CreateProduct", build("create_product").constant
    assert_equal "Catalogo::LineItems::LineItem", build("line_items/line_item").constant
  end

  def test_with_suffix_adds_suffix_to_last_segment
    name = build("product").with_suffix("schema")

    assert_equal "product_schema", name.relative_path
    assert_equal "Catalogo::ProductSchema", name.constant
  end

  def test_with_suffix_keeps_folders
    name = build("orders/line_item").with_suffix("schema")

    assert_equal "orders/line_item_schema", name.relative_path
    assert_equal "Catalogo::Orders::LineItemSchema", name.constant
  end

  def test_with_suffix_does_not_duplicate_suffix
    name = build("product_schema").with_suffix("schema")

    assert_equal "product_schema", name.relative_path
    assert_equal "Catalogo::ProductSchema", name.constant
  end

  def test_with_suffix_returns_new_object
    original = build("product")

    refute_same original, original.with_suffix("schema")
    assert_equal "product", original.relative_path
  end

  def test_rejects_invalid_names
    [
      "../x",
      "/x",
      "x/",
      "Products",
      "a b",
      "a//b",
      ""
    ].each do |name|
      error = assert_raises(Boto::CLI::Error, name) { build(name) }
      assert_includes error.message, %("#{name}")
    end
  end

  private

  def build(name) = Boto::CLI::ConstantName.new(name, namespace: NAMESPACE)
end
