# frozen_string_literal: true

require "test_helper"

class Boto::ProjectLoaderTest < Minitest::Test
  FIXTURE = File.expand_path("../fixtures/shop", __dir__)

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

  def test_setup_twice_does_not_fail
    assert_same @loader, @loader.setup
    assert_same @loader, @loader.setup
  end

  def test_namespace_reuses_existing_module
    @loader.setup
    namespace = Boto::ProjectLoader.new(@project, root: FIXTURE).namespace

    assert_same @loader.namespace, namespace
  end
end
