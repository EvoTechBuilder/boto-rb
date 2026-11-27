# frozen_string_literal: true

require "test_helper"
require "rack/mock"
require "json"
require "fileutils"
require "stringio"
require "tmpdir"

class Boto::ProjectAppTest < Minitest::Test
  FIXTURE = File.expand_path("../fixtures/environment", __dir__)
  LOJA_URL = "https://loja.test"
  PEDIDOS_URL = "https://pedidos.test"

  # Declared outside any booted project, so `app` has nothing to resolve to.
  class Loose < Boto::Operation
    def call = app
  end

  def setup
    @root = Dir.mktmpdir("boto-project-app")
    FileUtils.cp_r(File.join(FIXTURE, "."), @root)
    @boots = []
  end

  def teardown
    @boots.each(&:shutdown)
    FileUtils.remove_entry(@root)
  end

  def test_endpoint_reads_the_app_env_of_its_project
    write("apps/orders/.env", "FRONTEND_URL=#{LOJA_URL}\n")

    response = Rack::MockRequest.new(build_boot.app("orders")).get("/frontend")

    assert_equal({ "url" => LOJA_URL }, JSON.parse(response.body))
  end

  def test_operation_reads_the_app_env_of_its_project
    write("apps/orders/.env", "FRONTEND_URL=#{LOJA_URL}\n")
    build_boot.app("orders")

    assert_equal LOJA_URL, Orders::FrontendLink.call.value
  end

  def test_each_project_sees_only_its_own_app_env
    write("apps/orders/.env", "FRONTEND_URL=#{LOJA_URL}\n")
    write("apps/pedidos/.env", "FRONTEND_URL=#{PEDIDOS_URL}\n")
    boot = build_boot
    orders = boot.app("orders")
    pedidos = boot.app("pedidos")

    assert_equal LOJA_URL, JSON.parse(Rack::MockRequest.new(orders).get("/frontend").body)["url"]
    assert_equal PEDIDOS_URL, JSON.parse(Rack::MockRequest.new(pedidos).get("/frontend").body)["url"]
  end

  def test_endpoint_env_is_still_the_rack_env
    write("apps/orders/.env", "FRONTEND_URL=#{LOJA_URL}\n")
    build_boot.app("orders")
    rack_env = { Boto::Endpoint::PRINCIPAL_KEY => "ana" }

    endpoint = Orders::Frontend.new(rack_env)

    assert_same rack_env, endpoint.env
    assert_equal "ana", endpoint.principal
  end

  def test_app_is_the_same_object_on_every_call
    build_boot.app("orders")

    assert_same Orders.app, Orders::FrontendLink.send(:new).app
    assert_same Orders.app, Orders::Frontend.new({}).app
  end

  def test_class_outside_a_booted_project_raises_a_clear_error
    error = assert_raises(Boto::ProjectApp::NotBootedError) { Loose.call }

    assert_includes error.message, "is not in a booted project"
  end

  def test_anonymous_class_outside_a_booted_project_raises_a_clear_error
    klass = Class.new(Boto::Endpoint)

    assert_raises(Boto::ProjectApp::NotBootedError) { klass.new({}).app }
  end

  private

  def build_boot(env: {})
    boot = Boto::Boot.new(Boto::Botofile.load(File.join(@root, "Botofile")), root: @root,
                                                                            env: env, warn_output: StringIO.new)
    @boots << boot
    boot
  end

  def write(relative_path, content)
    path = File.join(@root, relative_path)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, content)
  end
end
