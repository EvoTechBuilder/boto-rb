# frozen_string_literal: true

require "test_helper"
require "sequel"

class ConnectionsTest < Minitest::Test
  module CatalogoTestShop; end

  def setup
    @database = Sequel.sqlite
  end

  def teardown
    Boto::Database::Connections.unregister(CatalogoTestShop)
    @database.disconnect
  end

  def test_register_then_for_returns_the_database
    Boto::Database::Connections.register(CatalogoTestShop, @database)

    assert_same @database, Boto::Database::Connections.for(CatalogoTestShop)
    assert Boto::Database::Connections.registered?(CatalogoTestShop)
  end

  def test_unregister_removes_the_database
    Boto::Database::Connections.register(CatalogoTestShop, @database)
    Boto::Database::Connections.unregister(CatalogoTestShop)

    refute Boto::Database::Connections.registered?(CatalogoTestShop)
  end

  def test_for_without_registration_explains_how_to_add_the_database
    error = assert_raises(Boto::Database::MissingDatabaseError) do
      Boto::Database::Connections.for(CatalogoTestShop)
    end

    assert_equal "#{CatalogoTestShop} has no database: add app.use :database, url: ... to its config/app.rb",
                 error.message
  end
end
