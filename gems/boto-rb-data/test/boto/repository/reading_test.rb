# frozen_string_literal: true

require "test_helper"
require "sequel"

module ReadingTestShop
  Product = Data.define(:id, :name, :price)

  class ProductRepository < Boto::Repository
    entity Product
    table :products

    def self.cheapest(limit: 10) = query { _1.order(:price).limit(limit) }
  end
end

class ReadingTest < Minitest::Test
  REPO = ReadingTestShop::ProductRepository
  PRODUCT = ReadingTestShop::Product
  SEED = [
    { name: "Caneca", price: 39.9 },
    { name: "Camiseta", price: 49.0 },
    { name: "Adesivo", price: 5.0 },
    { name: "Caneca", price: 12.0 },
    { name: nil, price: 1.0 }
  ].freeze

  def setup
    @db = Sequel.sqlite
    @db.create_table(:products) do
      primary_key :id
      String :name
      Float :price
      String :note # not in the entity: must be ignored when reading
    end
    @db[:products].multi_insert(SEED)
    Boto::Database::Connections.register(ReadingTestShop, @db)
  end

  def teardown
    Boto::Database::Connections.unregister(ReadingTestShop)
    @db.disconnect
  end

  def test_find_returns_the_entity_or_nil
    assert_equal PRODUCT.new(id: 1, name: "Caneca", price: 39.9), REPO.find(1)
    assert_nil REPO.find(99)
  end

  def test_find_bang_raises_not_found_with_the_entity_name
    error = assert_raises(Boto::Repository::NotFound) { REPO.find!(99) }

    assert_equal "ReadingTestShop::Product 99 not found", error.message
  end

  def test_all_is_ordered_by_id_by_default
    assert_equal [1, 2, 3, 4, 5], REPO.all.map(&:id)
  end

  def test_all_applies_order_limit_and_offset
    assert_equal [5, 3], REPO.all(order: :price, limit: 2).map(&:id)
    assert_equal [3, 4], REPO.all(order: :price, limit: 2, offset: 1).map(&:id)
  end

  def test_all_accepts_an_array_or_a_string_for_order
    assert_equal [5, 3, 4, 1, 2], REPO.all(order: [:price, :id]).map(&:id)
    assert_equal [5], REPO.all(order: "price", limit: 1).map(&:id)
  end

  def test_all_rejects_a_limit_or_offset_that_is_not_a_non_negative_integer
    assert_raises(ArgumentError) { REPO.all(limit: "10") }
    assert_raises(ArgumentError) { REPO.all(offset: -1) }
  end

  def test_where_with_a_range_is_inclusive
    assert_equal [1, 2, 4], REPO.where(price: 10..50).map(&:id)
    assert_equal [1, 4], REPO.where(price: 10...49).map(&:id)
  end

  def test_where_with_an_array_is_an_in_list
    assert_equal [2, 5], REPO.where(id: [2, 5]).map(&:id)
  end

  def test_where_with_nil_is_is_null
    assert_equal [5], REPO.where(name: nil).map(&:id)
  end

  def test_where_accepts_string_keys_and_combines_filters
    assert_equal [1, 4], REPO.where("name" => "Caneca").map(&:id)
    assert_equal [1], REPO.where(name: "Caneca", price: 39.9).map(&:id)
  end

  def test_where_takes_order_and_limit
    assert_equal [4], REPO.where(name: "Caneca", order: :price, limit: 1).map(&:id)
    assert_equal [3, 4], REPO.where(order: :price, limit: 2, offset: 1).map(&:id)
  end

  def test_find_by_each_member_returns_the_first_match_by_id_or_nil
    assert_equal 1, REPO.find_by_name("Caneca").id
    assert_equal 2, REPO.find_by_id(2).id
    assert_equal 4, REPO.find_by_price(12.0).id
    assert_equal 5, REPO.find_by_name(nil).id
    assert_nil REPO.find_by_name("nada")
  end

  def test_exists_with_and_without_filters
    assert REPO.exists?(name: "Adesivo")
    refute REPO.exists?(name: "nada")
    assert REPO.exists?

    @db[:products].delete

    refute REPO.exists?
  end

  def test_count_with_and_without_filters
    assert_equal 2, REPO.count(price: 0..10)
    assert_equal 2, REPO.count(name: "Caneca")
    assert_equal 5, REPO.count
  end

  def test_query_maps_the_rows_to_entities
    cheapest = REPO.cheapest(limit: 2)

    assert_equal [5, 3], cheapest.map(&:id)
    assert_kind_of PRODUCT, cheapest.first
  end

  def test_query_is_private_to_the_repository
    assert_raises(NoMethodError) { REPO.query { _1 } }
  end

  def test_unknown_field_in_filters_or_order_is_an_argument_error
    message = %(unknown field "color" for ReadingTestShop::Product)

    assert_equal message, assert_raises(ArgumentError) { REPO.where(color: "x") }.message
    assert_equal message, assert_raises(ArgumentError) { REPO.exists?(color: "x") }.message
    assert_equal message, assert_raises(ArgumentError) { REPO.count(color: "x") }.message
    assert_equal message, assert_raises(ArgumentError) { REPO.all(order: :color) }.message
  end

  def test_a_quote_in_find_by_does_not_change_the_query
    assert_nil REPO.find_by_name("x' OR '1'='1")
  end

  def test_a_drop_table_in_where_is_only_a_value
    assert_empty REPO.where(name: "'; DROP TABLE products; --")
    assert @db.table_exists?(:products)
    assert_equal 5, REPO.count
  end
end

# order, limit and offset are reserved in where: a field with one of those names is filtered through
# find_by_<field> or query, and exists? and count take any field name.
module ReservedTestShop
  Slot = Data.define(:id, :order, :limit)

  class SlotRepository < Boto::Repository
    entity Slot
    table :slots

    def self.named(value) = query { _1.where(order: value) }
  end
end

class ReservedWordsTest < Minitest::Test
  REPO = ReservedTestShop::SlotRepository

  def setup
    @db = Sequel.sqlite
    @db.create_table(:slots) do
      primary_key :id
      String :order
      Integer :limit
    end
    @db[:slots].multi_insert([{ order: "first", limit: 9 }, { order: "second", limit: 3 }])
    Boto::Database::Connections.register(ReservedTestShop, @db)
  end

  def teardown
    Boto::Database::Connections.unregister(ReservedTestShop)
    @db.disconnect
  end

  def test_find_by_filters_a_field_named_like_a_keyword
    assert_equal 1, REPO.find_by_order("first").id
    assert_equal 2, REPO.find_by_limit(3).id
  end

  def test_where_uses_the_keyword_as_ordering
    assert_equal [2, 1], REPO.where(order: :limit).map(&:id)
    assert_raises(ArgumentError) { REPO.where(order: "first") }
  end

  def test_query_filters_a_field_named_like_a_keyword
    assert_equal [1], REPO.named("first").map(&:id)
  end

  def test_exists_and_count_filter_a_field_named_like_a_keyword
    assert REPO.exists?(order: "second")
    assert_equal 1, REPO.count(limit: 9)
  end
end
