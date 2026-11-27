# frozen_string_literal: true

require "test_helper"

class Boto::CLI::EndpointConventionTest < Minitest::Test
  Convention = Boto::CLI::EndpointConvention
  Rule = Convention::Rule

  EXPECTED_RULES = {
    "index" => Rule.new(verb: "get", path: "/products", body: nil, returns: "[product]"),
    "show" => Rule.new(verb: "get", path: "/products/:id", body: nil, returns: "product"),
    "create" => Rule.new(verb: "post", path: "/products", body: "product_input", returns: "product"),
    "update" => Rule.new(verb: "patch", path: "/products/:id", body: "product_input", returns: "product"),
    "destroy" => Rule.new(verb: "delete", path: "/products/:id", body: nil, returns: nil),
    "search" => Rule.new(verb: "query", path: "/products/search", body: "product_filter", returns: "[product]")
  }.freeze

  def test_derives_rule_for_each_known_action
    EXPECTED_RULES.each do |action, expected|
      assert_equal expected, Convention.for("products/#{action}"), action
    end
  end

  def test_nested_folders_form_the_route_base
    expected = Rule.new(verb: "get", path: "/admin/products/:id", body: nil, returns: "product")

    assert_equal expected, Convention.for("admin/products/show")
  end

  def test_unknown_action_returns_nil
    assert_nil Convention.for("products/publish")
  end

  def test_name_without_folder_returns_nil
    assert_nil Convention.for("show")
  end

  def test_known_actions_are_frozen_in_table_order
    assert_equal %w[index show create update destroy search], Convention::KNOWN_ACTIONS
    assert_predicate Convention::KNOWN_ACTIONS, :frozen?
  end

  def test_singular_of_plural_words
    assert_equal "product", Convention.singular("products")
    assert_equal "category", Convention.singular("categories")
    assert_equal "pedido", Convention.singular("pedidos")
  end

  def test_singular_keeps_words_that_are_not_plural
    assert_equal "address", Convention.singular("address")
    assert_equal "data", Convention.singular("data")
  end

  def test_singular_strips_s_from_status
    assert_equal "statu", Convention.singular("status")
  end
end
