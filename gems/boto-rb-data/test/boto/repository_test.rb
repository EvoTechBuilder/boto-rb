# frozen_string_literal: true

require "test_helper"
require "sequel"

module RepositoryTestShop
  Item = Data.define(:id, :name)

  class ItemRepository < Boto::Repository
    entity Item
    table :items
  end

  class NoEntityRepository < Boto::Repository
    table :items
  end

  class NoTableRepository < Boto::Repository
    entity Item
  end
end

class RepositoryTest < Minitest::Test
  def setup
    @db = Sequel.sqlite
    @db.create_table(:items) do
      primary_key :id
      String :name
    end
    @db[:items].insert(name: "Caneca")
    Boto::Database::Connections.register(RepositoryTestShop, @db)
  end

  def teardown
    Boto::Database::Connections.unregister(RepositoryTestShop)
    @db.disconnect
  end

  def test_declared_needs_both_an_entity_and_a_table
    assert RepositoryTestShop::ItemRepository.declared?
    refute RepositoryTestShop::NoEntityRepository.declared?
    refute RepositoryTestShop::NoTableRepository.declared?
  end

  def test_entity_defines_a_finder_for_each_member
    assert_respond_to RepositoryTestShop::ItemRepository, :find_by_id
    assert_respond_to RepositoryTestShop::ItemRepository, :find_by_name
  end

  def test_check_passes_when_every_member_is_a_column
    assert_nil RepositoryTestShop::ItemRepository.check!(@db)
  end

  def test_check_names_the_missing_column
    db = Sequel.sqlite
    db.create_table(:items) { primary_key :id }

    error = assert_raises(Boto::Repository::SchemaMismatch) { RepositoryTestShop::ItemRepository.check!(db) }

    assert_equal %(RepositoryTestShop::ItemRepository: column "name" of RepositoryTestShop::Item ) +
                 "is missing in table items", error.message
  ensure
    db&.disconnect
  end

  def test_check_names_a_missing_table
    db = Sequel.sqlite

    error = assert_raises(Boto::Repository::SchemaMismatch) { RepositoryTestShop::ItemRepository.check!(db) }

    assert_equal "RepositoryTestShop::ItemRepository: table items does not exist", error.message
  ensure
    db&.disconnect
  end

  def test_a_repository_without_entity_explains_how_to_declare_it
    error = assert_raises(Boto::Repository::MissingDeclarationError) do
      RepositoryTestShop::NoEntityRepository.find(1)
    end

    assert_equal "RepositoryTestShop::NoEntityRepository has no entity; declare it with `entity YourData`",
                 error.message
  end

  def test_a_repository_without_table_explains_how_to_declare_it
    error = assert_raises(Boto::Repository::MissingDeclarationError) do
      RepositoryTestShop::NoTableRepository.find(1)
    end

    assert_equal "RepositoryTestShop::NoTableRepository has no table; declare it with `table :name`", error.message
  end

  def test_a_repository_without_a_database_explains_how_to_add_one
    Boto::Database::Connections.unregister(RepositoryTestShop)

    error = assert_raises(Boto::Database::MissingDatabaseError) { RepositoryTestShop::ItemRepository.find(1) }

    assert_includes error.message, "add app.use :database"
  end

  def test_the_connection_is_read_on_each_call
    other = Sequel.sqlite
    other.create_table(:items) { primary_key :id; String :name }
    other[:items].insert(name: "Outra")
    assert_equal "Caneca", RepositoryTestShop::ItemRepository.find(1).name

    Boto::Database::Connections.register(RepositoryTestShop, other)

    assert_equal "Outra", RepositoryTestShop::ItemRepository.find(1).name
  ensure
    other&.disconnect
  end
end
