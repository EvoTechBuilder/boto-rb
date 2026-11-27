# frozen_string_literal: true

require "test_helper"

class Boto::CLI::EndpointRouteTest < Minitest::Test
  def test_accepts_every_verb
    Boto::CLI::EndpointRoute::VERBS.each do |verb|
      assert_equal verb, parse(verb, "/x").verb
    end
  end

  def test_lists_the_path_params_in_order
    assert_equal %w[shop_id id], parse("get", "/shops/:shop_id/products/:id").param_names
  end

  def test_path_without_params_has_none
    assert_empty parse("get", "/products").param_names
  end

  def test_rejects_an_unknown_verb
    error = assert_raises(Boto::CLI::Error) { parse("GET", "/products") }

    assert_equal %(unknown verb "GET" (available: get, post, put, patch, delete, query)), error.message
  end

  def test_rejects_a_path_without_a_leading_slash
    assert_invalid_path "products"
  end

  def test_rejects_characters_outside_the_route_alphabet
    assert_invalid_path %(/products?x="y")
    assert_invalid_path "/products/{id}"
  end

  def test_rejects_a_param_name_that_is_not_an_identifier
    error = assert_raises(Boto::CLI::Error) { parse("get", "/products/:Id") }

    assert_equal %(invalid path param ":Id" in /products/:Id), error.message
  end

  private

  def parse(verb, path) = Boto::CLI::EndpointRoute.parse(verb, path)

  def assert_invalid_path(path)
    error = assert_raises(Boto::CLI::Error) { parse("get", path) }
    assert_includes error.message, %(invalid path "#{path}")
  end
end
