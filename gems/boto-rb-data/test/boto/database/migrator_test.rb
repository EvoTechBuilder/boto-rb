# frozen_string_literal: true

require "test_helper"
require "sequel"
require "fileutils"
require "tmpdir"

class Boto::Database::MigratorTest < Minitest::Test
  PRODUCTS = "20261127120000_create_products.rb"
  ORDERS = "20261127120100_create_orders.rb"

  # SQLite in a file, not :memory:, because Sequel gives each pooled connection its own memory database.
  def setup
    @tmp = Dir.mktmpdir("boto-migrator")
    @dir = File.join(@tmp, "db", "migrations")
    FileUtils.mkdir_p(@dir)
    @db = Sequel.sqlite(File.join(@tmp, "app.db"))
    write(PRODUCTS, "products")
    write(ORDERS, "orders")
  end

  def teardown
    @db.disconnect
    FileUtils.remove_entry(@tmp)
  end

  def test_migrate_applies_every_pending_migration
    assert_equal [PRODUCTS, ORDERS], migrator.migrate
    assert @db.table_exists?(:products)
    assert @db.table_exists?(:orders)
  end

  def test_migrate_again_applies_nothing
    migrator.migrate

    assert_equal [], migrator.migrate
  end

  def test_status_lists_each_file_as_down_until_applied
    assert_equal [[PRODUCTS, :down], [ORDERS, :down]], migrator.status

    migrator.migrate

    assert_equal [[PRODUCTS, :up], [ORDERS, :up]], migrator.status
  end

  def test_rollback_undoes_only_the_last_migration
    migrator.migrate

    assert_equal [ORDERS], migrator.rollback(steps: 1)
    refute @db.table_exists?(:orders)
    assert @db.table_exists?(:products)
    assert_equal [[PRODUCTS, :up], [ORDERS, :down]], migrator.status
  end

  def test_rollback_with_more_steps_than_applied_undoes_all_newest_first
    migrator.migrate

    assert_equal [ORDERS, PRODUCTS], migrator.rollback(steps: 5)
    refute @db.table_exists?(:products)
  end

  def test_rollback_without_applied_migrations_does_nothing
    assert_equal [], migrator.rollback
  end

  def test_rollback_refuses_invalid_steps
    [0, -1, "1", nil, 1.5].each do |steps|
      assert_raises(ArgumentError) { migrator.rollback(steps: steps) }
    end
  end

  def test_empty_directory_has_no_migrations
    empty = File.join(@tmp, "empty")
    FileUtils.mkdir_p(empty)

    assert_equal [], Boto::Database::Migrator.new(@db, empty).migrate
    assert_equal [], Boto::Database::Migrator.new(@db, empty).status
  end

  def test_missing_directory_has_no_migrations
    missing = Boto::Database::Migrator.new(@db, File.join(@tmp, "nao-existe"))

    assert_equal [], missing.migrate
    assert_equal [], missing.status
  end

  private

  def migrator = Boto::Database::Migrator.new(@db, @dir)

  def write(name, table)
    File.write(File.join(@dir, name), <<~RUBY)
      Sequel.migration do
        change do
          create_table(:#{table}) { primary_key :id }
        end
      end
    RUBY
  end
end
