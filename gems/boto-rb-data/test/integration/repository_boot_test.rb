# frozen_string_literal: true

require "test_helper"
require "fileutils"
require "sequel"
require "stringio"
require "tmpdir"

module RepositoryBootShop
  Thing = Data.define(:id, :price)

  class ThingRepository < Boto::Repository
    entity Thing
    table :things
  end
end

class RepositoryBootIntegrationTest < Minitest::Test
  def setup
    @dir = Dir.mktmpdir
    @path = File.join(@dir, "shop.sqlite3")
  end

  def teardown
    @app&.stop
    FileUtils.remove_entry(@dir)
  end

  def test_boot_fails_when_a_repository_column_is_missing
    create_things_table { primary_key :id }
    @app = app_with_database

    error = assert_raises(Boto::App::BootError) { @app.start }

    assert_includes error.message, %(column "price" of RepositoryBootShop::Thing is missing in table things)
    refute Boto::Database::Connections.registered?(RepositoryBootShop)
  end

  def test_boot_succeeds_when_the_table_matches_the_entity
    create_things_table do
      primary_key :id
      Float :price
    end
    @app = app_with_database

    @app.start

    assert Boto::Database::Connections.registered?(RepositoryBootShop)
    assert_nil RepositoryBootShop::ThingRepository.find(1)
  end

  private

  def create_things_table(&columns)
    db = Sequel.sqlite(@path)
    db.create_table(:things, &columns)
    db.disconnect
  end

  def app_with_database
    config = Boto::Configuration.new(env_name: "test").use(:database, url: "sqlite://#{@path}")
    Boto::App.new(namespace: RepositoryBootShop, plugins: config.plugins, env_name: "test",
                  error_output: StringIO.new)
  end
end
