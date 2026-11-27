# frozen_string_literal: true

require "test_helper"
require "sequel"

module WritingTestShop
  Product = Data.define(:id, :name, :price, :created_at, :updated_at)
  Item = Data.define(:id, :name, :price)
  Order = Data.define(:id, :product_id)

  class ProductRepository < Boto::Repository
    entity Product
    table :products
  end

  class ItemRepository < Boto::Repository
    entity Item
    table :items
  end

  class OrderRepository < Boto::Repository
    entity Order
    table :orders
  end
end

class WritingTest < Minitest::Test
  PRODUCT_REPO = WritingTestShop::ProductRepository
  ITEM_REPO = WritingTestShop::ItemRepository
  ORDER_REPO = WritingTestShop::OrderRepository
  PRODUCT = WritingTestShop::Product
  # UTC on purpose: boto-rb-data stores and reads times in UTC, so a UTC clock round-trips unchanged.
  NOW = Time.utc(2026, 11, 27, 12)
  LATER = Time.utc(2026, 11, 27, 13)
  BOOM = Class.new(StandardError)

  def setup
    @now = NOW
    @db = Sequel.sqlite
    @db.run("PRAGMA foreign_keys = ON")
    create_tables
    Boto::Database::Connections.register(WritingTestShop, @db)
    PRODUCT_REPO.clock = -> { @now }
  end

  def teardown
    PRODUCT_REPO.clock = nil
    Boto::Database::Connections.unregister(WritingTestShop)
    @db.disconnect
  end

  def test_create_returns_the_entity_with_id_and_timestamps
    product = PRODUCT_REPO.create(name: "Caneca", price: 39.9)

    assert_equal PRODUCT.new(id: 1, name: "Caneca", price: 39.9, created_at: NOW, updated_at: NOW), product
  end

  def test_create_without_timestamps_in_the_entity
    item = ITEM_REPO.create(name: "Caneca", price: 39.9)

    assert_equal WritingTestShop::Item.new(id: 1, name: "Caneca", price: 39.9), item
  end

  def test_create_accepts_string_keys
    assert_equal "Caneca", PRODUCT_REPO.create("name" => "Caneca", "price" => 1.0).name
  end

  def test_update_changes_the_row_and_bumps_updated_at
    PRODUCT_REPO.create(name: "Caneca", price: 39.9)
    @now = LATER

    product = PRODUCT_REPO.update(1, price: 29.9)

    assert_equal 29.9, product.price
    assert_equal NOW, product.created_at
    assert_equal LATER, product.updated_at
    assert_equal 29.9, PRODUCT_REPO.find(1).price
  end

  def test_update_of_a_missing_id_returns_nil
    assert_nil PRODUCT_REPO.update(99, price: 1.0)
  end

  def test_update_without_attributes_returns_the_current_entity_and_changes_nothing
    created = PRODUCT_REPO.create(name: "Caneca", price: 39.9)
    @now = LATER

    assert_equal created, PRODUCT_REPO.update(1)
    assert_equal NOW, PRODUCT_REPO.find(1).updated_at
    assert_nil PRODUCT_REPO.update(99)
  end

  def test_delete_returns_true_when_the_row_existed
    PRODUCT_REPO.create(name: "Caneca", price: 39.9)

    assert PRODUCT_REPO.delete(1)
    refute PRODUCT_REPO.exists?(id: 1)
  end

  def test_delete_returns_false_when_the_row_did_not_exist
    refute PRODUCT_REPO.delete(99)
  end

  def test_create_refuses_managed_fields
    %i[id created_at updated_at].each do |field|
      error = assert_raises(ArgumentError) { PRODUCT_REPO.create(field => 1, name: "x", price: 1.0) }

      assert_equal %(field "#{field}" is managed by the repository), error.message
    end
  end

  def test_update_refuses_managed_fields
    PRODUCT_REPO.create(name: "Caneca", price: 39.9)

    error = assert_raises(ArgumentError) { PRODUCT_REPO.update(1, "id" => 9) }

    assert_equal %(field "id" is managed by the repository), error.message
  end

  def test_create_and_update_refuse_an_unknown_field
    message = %(unknown field "color" for WritingTestShop::Product)
    PRODUCT_REPO.create(name: "Caneca", price: 39.9)

    assert_equal message, assert_raises(ArgumentError) { PRODUCT_REPO.create(name: "x", color: "red") }.message
    assert_equal message, assert_raises(ArgumentError) { PRODUCT_REPO.update(1, color: "red") }.message
  end

  def test_create_with_a_duplicate_unique_field_raises_unique_violation
    PRODUCT_REPO.create(name: "Caneca", price: 39.9)

    error = assert_raises(Boto::Repository::UniqueViolation) { PRODUCT_REPO.create(name: "Caneca", price: 1.0) }

    assert_equal "WritingTestShop::Product: unique constraint violated", error.message
    refute_includes error.message, "Caneca"
    assert_kind_of Sequel::UniqueConstraintViolation, error.cause
  end

  def test_update_to_a_duplicate_unique_field_raises_unique_violation
    PRODUCT_REPO.create(name: "Caneca", price: 39.9)
    PRODUCT_REPO.create(name: "Camiseta", price: 49.0)

    assert_raises(Boto::Repository::UniqueViolation) { PRODUCT_REPO.update(2, name: "Caneca") }
  end

  def test_create_with_a_missing_foreign_key_raises_foreign_key_violation
    error = assert_raises(Boto::Repository::ForeignKeyViolation) { ORDER_REPO.create(product_id: 99) }

    assert_equal "WritingTestShop::Order: foreign key constraint violated", error.message
    assert_kind_of Sequel::ForeignKeyConstraintViolation, error.cause
  end

  def test_delete_of_a_referenced_row_raises_foreign_key_violation
    PRODUCT_REPO.create(name: "Caneca", price: 39.9)
    ORDER_REPO.create(product_id: 1)

    assert_raises(Boto::Repository::ForeignKeyViolation) { PRODUCT_REPO.delete(1) }
  end

  def test_transaction_commits_the_block
    PRODUCT_REPO.transaction { PRODUCT_REPO.create(name: "Caneca", price: 39.9) }

    assert_equal 1, PRODUCT_REPO.count
  end

  def test_transaction_rolls_back_and_reraises_on_an_exception
    assert_raises(BOOM) do
      PRODUCT_REPO.transaction do
        PRODUCT_REPO.create(name: "Caneca", price: 39.9)
        raise BOOM
      end
    end

    assert_equal 0, PRODUCT_REPO.count
  end

  def test_quotes_in_values_are_stored_literally
    value = "x' OR '1'='1"
    created = PRODUCT_REPO.create(name: value, price: 1.0)

    assert_equal value, created.name
    updated = PRODUCT_REPO.update(created.id, name: "a'b\"c")

    assert_equal "a'b\"c", updated.name
    assert_equal "a'b\"c", PRODUCT_REPO.find(created.id).name
  end

  private

  def create_tables
    @db.create_table(:products) do
      primary_key :id
      String :name, unique: true
      Float :price
      DateTime :created_at
      DateTime :updated_at
    end
    @db.create_table(:items) do
      primary_key :id
      String :name
      Float :price
    end
    @db.create_table(:orders) do
      primary_key :id
      foreign_key :product_id, :products, null: false
    end
  end
end
