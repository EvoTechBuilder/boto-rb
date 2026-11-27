# frozen_string_literal: true

require "test_helper"

# Only this namespace has a repository, so the other plugin tests never run the schema check.
module SchemaCheckShop
  Thing = Data.define(:id, :price)

  class ThingRepository < Boto::Repository
    entity Thing
    table :things
  end
end

class DatabasePluginTest < Minitest::Test
  MEMORY_URL = "sqlite::memory:"
  SECRET_URL = "postgres://app:s3cret@127.0.0.1:1/shop"
  MISSING_DIR_URL = "sqlite:///nao/existe/x.db"

  def setup
    @plugins = []
  end

  def teardown
    @plugins.each(&:stop)
    Boto::Database::Connections.unregister(DatabaseTestShop)
  end

  def test_pool_must_be_a_positive_integer
    [0, "x", 2.0].each do |pool|
      error = assert_raises(ArgumentError) { build_plugin(pool: pool) }

      assert_equal "database: pool must be a positive Integer", error.message
    end
  end

  def test_url_must_be_a_non_empty_string
    error = assert_raises(ArgumentError) { build_plugin(url: "  ") }

    assert_equal "database: url must be a non-empty String or a callable that returns one", error.message
  end

  def test_callable_url_is_resolved_at_configure_time
    plugin = build_plugin(url: -> { MEMORY_URL })

    assert_includes plugin.inspect, MEMORY_URL
  end

  def test_callable_url_with_a_missing_secret_fails_at_boot
    assert_raises(KeyError) { build_plugin(url: -> { {}.fetch("DATABASE_URL") }) }
  end

  def test_start_registers_and_stop_unregisters
    plugin = start_plugin

    assert Boto::Database::Connections.registered?(DatabaseTestShop)

    plugin.stop

    refute Boto::Database::Connections.registered?(DatabaseTestShop)
  end

  def test_stop_twice_does_not_fail
    plugin = start_plugin

    plugin.stop
    plugin.stop

    refute Boto::Database::Connections.registered?(DatabaseTestShop)
  end

  def test_database_health_check_is_ok_with_a_working_connection
    plugin = start_plugin

    assert plugin.health_checks.fetch(:database).call
  end

  def test_connection_failure_hides_the_url
    plugin = build_plugin(url: MISSING_DIR_URL)
    plugin.attach(app_named(DatabaseTestShop))

    error = assert_raises(Boto::Database::ConnectionError) { plugin.start }

    assert_equal "database: could not connect (Sequel::DatabaseConnectionError)", error.message
    refute_includes error.message, "nao/existe"
    assert_nil error.cause
    refute Boto::Database::Connections.registered?(DatabaseTestShop)
  end

  def test_connection_failure_does_not_leak_the_password
    plugin = build_plugin(url: SECRET_URL)
    plugin.attach(app_named(DatabaseTestShop))

    error = assert_raises(Boto::Database::ConnectionError) { plugin.start }

    refute_includes error.message, "s3cret"
    refute_includes error.message, "127.0.0.1"
    assert_nil error.cause
  end

  def test_inspect_masks_the_password
    plugin = build_plugin(url: SECRET_URL)

    assert_includes plugin.inspect, "postgres://app:***@127.0.0.1:1/shop"
    refute_includes plugin.inspect, "s3cret"
  end

  def test_start_fails_when_a_repository_has_no_table_and_registers_nothing
    plugin = build_plugin
    plugin.attach(app_named(SchemaCheckShop))

    error = assert_raises(Boto::Repository::SchemaMismatch) { plugin.start }

    assert_equal "SchemaCheckShop::ThingRepository: table things does not exist", error.message
    refute Boto::Database::Connections.registered?(SchemaCheckShop)
  end

  def test_each_fiber_gets_its_own_connection
    start_plugin(pool: 2)
    database = Boto::Database::Connections.for(DatabaseTestShop)
    holder = Fiber.new { database.synchronize { |connection| Fiber.yield connection } }
    first = holder.resume
    second = database.synchronize { |connection| connection }

    refute_same first, second
    holder.resume
  end

  def test_open_connection_returns_a_new_unregistered_database
    plugin = build_plugin
    database = plugin.open_connection
    other = plugin.open_connection

    assert_instance_of Sequel::SQLite::Database, database
    refute_same database, other
    refute Boto::Database::Connections.registered?(DatabaseTestShop)
    assert database.test_connection
  ensure
    [database, other].compact.each(&:disconnect)
  end

  def test_open_connection_hides_the_url_on_failure
    error = assert_raises(Boto::Database::ConnectionError) { build_plugin(url: MISSING_DIR_URL).open_connection }

    assert_equal "database: could not connect (Sequel::DatabaseConnectionError)", error.message
  end

  private

  def build_plugin(**options)
    options = { url: MEMORY_URL }.merge(options)
    Boto::Plugins::Database.new(env_name: "test", **options)
  end

  def start_plugin(**options)
    plugin = build_plugin(**options)
    plugin.attach(app_named(DatabaseTestShop))
    @plugins << plugin
    plugin.start
    plugin
  end

  def app_named(namespace)
    Struct.new(:title).new(namespace.name)
  end
end
