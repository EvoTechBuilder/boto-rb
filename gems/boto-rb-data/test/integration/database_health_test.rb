# frozen_string_literal: true

require "test_helper"
require "json"
require "rack/mock"
require "stringio"

module DatabaseHealthShop
end

class DatabaseHealthIntegrationTest < Minitest::Test
  def setup
    config = Boto::Configuration.new(env_name: "test")
                                .use(:health)
                                .use(:database, url: "sqlite::memory:")
    @app = Boto::App.new(namespace: DatabaseHealthShop, plugins: config.plugins, env_name: "test",
                         error_output: StringIO.new)
  end

  def teardown
    @app.stop
  end

  def test_ready_answers_200_with_database_ok
    @app.start

    response = Rack::MockRequest.new(@app).get("/health/ready")

    assert_equal 200, response.status
    assert_equal "ok", JSON.parse(response.body).dig("checks", "database")
  end

  def test_start_and_stop_register_and_unregister_the_namespace
    @app.start
    assert Boto::Database::Connections.registered?(DatabaseHealthShop)

    @app.stop
    refute Boto::Database::Connections.registered?(DatabaseHealthShop)
  end
end
