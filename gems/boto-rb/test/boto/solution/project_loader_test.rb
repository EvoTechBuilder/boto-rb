# frozen_string_literal: true

require "test_helper"

class Boto::ProjectLoaderTest < Minitest::Test
  FIXTURE = File.expand_path("../../fixtures/shop", __dir__)

  def setup
    @project = Boto::Botofile.load(File.join(FIXTURE, "Botofile")).project("domain")
    @loader = Boto::ProjectLoader.new(@project, root: FIXTURE)
  end

  def teardown
    @loader.unload
  end

  def test_setup_ignores_missing_code_directories
    @loader.setup

    assert_equal "hello ana", Domain::Greeting.call("ana")
  end

  def test_setup_loads_schemas_directory_when_present
    project = Boto::Botofile.load(File.join(FIXTURE, "Botofile")).project("orders")
    @loader = Boto::ProjectLoader.new(project, root: FIXTURE).setup

    assert_equal "Orders::GreetingSchema", Orders::GreetingSchema.name
  end

  def test_setup_twice_does_not_fail
    assert_same @loader, @loader.setup
    assert_same @loader, @loader.setup
  end

  def test_namespace_reuses_existing_module
    @loader.setup
    namespace = Boto::ProjectLoader.new(@project, root: FIXTURE).namespace

    assert_same @loader.namespace, namespace
  end

  def test_unload_removes_eager_loaded_constants
    @loader.eager_load
    assert defined?(Domain::Greeting)

    @loader.unload

    refute Domain.const_defined?(:Greeting, false)
    @loader = Boto::ProjectLoader.new(@project, root: FIXTURE).setup # teardown unloads a set-up loader
  end

  def test_unload_unregisters_even_when_zeitwerk_unload_fails
    @loader.setup
    zeitwerk = @loader.instance_variable_get(:@loader)
    unregistered = false

    with_singleton_method(zeitwerk, :unload, -> { raise "unload boom" }) do
      with_singleton_method(zeitwerk, :unregister, -> { unregistered = true }) do
        assert_raises(RuntimeError) { @loader.unload }
      end
    end

    assert unregistered
  end

  private

  # Replaces a method on one object only, and removes the replacement even if the block fails.
  def with_singleton_method(object, name, body)
    object.define_singleton_method(name, &body)
    yield
  ensure
    object.singleton_class.remove_method(name)
  end
end
