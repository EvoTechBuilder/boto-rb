# frozen_string_literal: true

require "test_helper"
require "rack/mock"
require "stringio"
require_relative "../../fixtures/boot_test_plugins"

class Boto::BootTest < Minitest::Test
  FIXTURE = File.expand_path("../../fixtures/shop", __dir__)

  def setup
    @boot = Boto::Boot.new(Boto::Botofile.load(File.join(FIXTURE, "Botofile")), root: FIXTURE,
                                                                              env: {}, warn_output: StringIO.new)
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

  def test_projects_are_verified_once_per_boot_instance
    @boot.load("orders")
    @boot.load("orders")

    assert_equal %w[domain orders], @boot.checked_projects.to_a.sort
  end
end

class Boto::BootIsolationTest < Minitest::Test
  FIXTURE = File.expand_path("../../fixtures/leaky", __dir__)
  PING = "services/lkorders/endpoints/ping.rb"

  def setup
    @warnings = StringIO.new
    @boot = build_boot(env: {}, warn_output: @warnings)
    @skipping_boot = build_boot(env: { Boto::Boot::SKIP_ENV => "1" }, warn_output: @warnings)
  end

  def teardown
    @boot.shutdown
    @skipping_boot.shutdown
  end

  def test_app_refuses_to_load_project_with_undeclared_use
    error = assert_raises(Boto::IsolationError) { @boot.app("lkorders") }

    assert_includes error.message, PING
    assert_includes error.message, "Lkdomain::Thing"
    assert_includes error.message, "Fix: boto ref lkorders lkdomain"
  end

  # Constants survive shutdown (also true for the shop fixture), so check that no fixture file was required.
  def test_refused_project_loads_nothing_and_is_not_marked_checked
    features_before = $LOADED_FEATURES.dup

    assert_raises(Boto::IsolationError) { @boot.app("lkorders") }

    assert_empty @boot.checked_projects
    assert_empty ($LOADED_FEATURES - features_before).select { _1.start_with?(FIXTURE) }
  end

  def test_skip_env_lets_the_project_load_and_warns_once
    @skipping_boot.load("lkorders")
    @skipping_boot.load("lkorders")

    assert_equal "Lkorders::Ping", Lkorders::Ping.name
    assert_equal "#{Boto::Boot::SKIP_WARNING}\n", @warnings.string
  end

  private

  def build_boot(env:, warn_output:)
    Boto::Boot.new(Boto::Botofile.load(File.join(FIXTURE, "Botofile")), root: FIXTURE,
                                                                       env: env, warn_output: warn_output)
  end
end

class Boto::BootConfigTest < Minitest::Test
  FIXTURE = File.expand_path("../../fixtures/stamped", __dir__)

  def setup
    @boot = Boto::Boot.new(Boto::Botofile.load(File.join(FIXTURE, "Botofile")), root: FIXTURE,
                                                                              env: {}, warn_output: StringIO.new)
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

class Boto::BootLifecycleTest < Minitest::Test
  FIXTURE = File.expand_path("../../fixtures/lifecycle", __dir__)
  EVENTS = []

  # Logs start and stop, and whether the probe constant is still loaded when the plugin stops.
  class Recorder < Boto::Plugin
    def configure(label:, probe:)
      @label = label
      @probe = probe
    end

    def start = EVENTS << [:start, @label]
    def stop = EVENTS << [:stop, @label, Object.const_defined?(@probe)]
  end

  class FailingStart < Boto::Plugin
    def start = raise("cannot start")
  end

  def setup
    EVENTS.clear
    @boot = Boto::Boot.new(Boto::Botofile.load(File.join(FIXTURE, "Botofile")), root: FIXTURE,
                                                                               env: {}, warn_output: StringIO.new)
  end

  def teardown
    @boot.shutdown
  end

  def test_app_is_started_before_it_is_returned
    @boot.app("lc_shop")

    assert_equal [[:start, "lc_shop"]], EVENTS
  end

  def test_shutdown_stops_apps_while_project_code_is_still_loaded
    @boot.app("lc_shop")
    @boot.shutdown

    assert_equal [[:start, "lc_shop"], [:stop, "lc_shop", true]], EVENTS
  end

  def test_shutdown_twice_stops_each_app_once
    @boot.app("lc_shop")
    @boot.shutdown
    @boot.shutdown

    assert_equal 1, EVENTS.count { |event| event.first == :stop }
  end

  def test_app_whose_plugin_fails_to_start_raises_and_is_not_stopped_again
    error = assert_raises(Boto::App::BootError) { @boot.app("lc_broken") }
    assert_includes error.message, "failing_start"
    started_then_stopped = [[:start, "lc_broken"], [:stop, "lc_broken", true]]
    assert_equal started_then_stopped, EVENTS

    @boot.shutdown

    assert_equal started_then_stopped, EVENTS
  end
end
