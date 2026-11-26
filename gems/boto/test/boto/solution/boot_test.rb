# frozen_string_literal: true

require "test_helper"
require "rack/mock"
require_relative "../../fixtures/boot_test_plugins"

class Boto::BootTest < Minitest::Test
  FIXTURE = File.expand_path("../../fixtures/shop", __dir__)

  def setup
    @boot = Boto::Boot.new(Boto::Botofile.load(File.join(FIXTURE, "Botofile")), root: FIXTURE)
  end

  def teardown
    @boot.shutdown
  end

  def test_app_serves_endpoints_of_the_project_and_its_dependencies
    request = Rack::MockRequest.new(@boot.app("orders"))

    assert_equal '{"message":"hello ana"}', request.get("/greet/ana").body
  end

  def test_app_loads_schemas_of_the_project
    app = @boot.app("orders")

    assert_equal "Orders::GreetingSchema", Orders::GreetingSchema.name
    assert_equal '{"message":"hello ana"}', Rack::MockRequest.new(app).get("/greet/ana").body
  end

  def test_app_serves_nested_endpoint_directories
    request = Rack::MockRequest.new(@boot.app("orders"))

    assert_equal '{"name":"bia"}', request.get("/customers/bia").body
  end

  def test_app_discovers_only_endpoints_of_its_own_namespace
    app = @boot.app("orders")

    assert_equal ["Orders::Customers::Show", "Orders::Greet"], app.endpoints.map(&:name)
  end

  def test_load_returns_the_namespace_module_of_the_project
    namespace = @boot.load("domain")

    assert_equal "Domain", namespace.name
    assert_equal "hello bia", namespace::Greeting.call("bia")
  end

  def test_load_twice_reuses_cached_loaders
    @boot.load("orders")

    assert_equal "Orders", @boot.load("orders").name
  end

  def test_load_unknown_project_raises_key_error
    assert_raises(KeyError) { @boot.load("missing") }
  end
end

class Boto::BootConfigTest < Minitest::Test
  FIXTURE = File.expand_path("../../fixtures/stamped", __dir__)

  def setup
    @boot = Boto::Boot.new(Boto::Botofile.load(File.join(FIXTURE, "Botofile")), root: FIXTURE)
  end

  def teardown
    @boot.shutdown
  end

  def test_app_applies_plugins_declared_in_config_app_rb
    res = Rack::MockRequest.new(@boot.app("stamp_shop", env_name: "production")).get("/ping")

    assert_equal "1", res.headers["x-stamp"]
    assert_equal '{"pong":true}', res.body
  end
end
