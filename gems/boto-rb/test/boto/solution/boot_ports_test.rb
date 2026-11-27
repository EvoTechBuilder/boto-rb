# frozen_string_literal: true

require "test_helper"
require "fileutils"
require "stringio"
require "tmpdir"

class Boto::BootPortsTest < Minitest::Test
  FIXTURE = File.expand_path("../../fixtures/environment", __dir__)

  def setup
    @root = Dir.mktmpdir("boto-ports")
    FileUtils.cp_r(File.join(FIXTURE, "."), @root)
    @boots = []
  end

  def teardown
    @boots.each(&:shutdown)
    FileUtils.remove_entry(@root)
  end

  def test_port_becomes_the_app_port_and_the_env_port
    app = build_boot(env: { "PORT" => "9999" }, ports: { "orders" => 4101 }).app("orders")

    assert_equal 4101, app.port
    assert_equal "4101", app.env.fetch("PORT")
    assert_equal "boto run", app.env.source("PORT")
  end

  def test_port_origin_is_the_project_file_that_declares_the_same_port
    write("apps/orders/.env", "PORT=4101\n")

    app = build_boot(ports: { "orders" => 4101 }).app("orders")

    assert_equal "apps/orders/.env", app.env.source("PORT")
  end

  def test_port_origin_is_boto_run_when_the_project_file_declares_another_port
    write("apps/orders/.env", "PORT=5000\n")

    app = build_boot(ports: { "orders" => 4101 }).app("orders")

    assert_equal ["4101", "boto run"], [app.env.fetch("PORT"), app.env.source("PORT")]
  end

  def test_port_is_listed_in_file_keys
    app = build_boot(ports: { "orders" => 4101 }).app("orders")

    assert_includes app.env.file_keys, "PORT"
  end

  def test_without_a_port_the_app_has_no_port_and_the_env_is_unchanged
    app = build_boot(env: { "PORT" => "9999" }).app("orders")

    assert_nil app.port
    assert_equal ["9999", "process"], [app.env.fetch("PORT"), app.env.source("PORT")]
  end

  def test_sources_name_the_layer_of_each_value
    write(".env", "SOLUTION_KEY=solution\n")
    write("apps/orders/.env", "PROJECT_KEY=project\n")

    env = build_boot(env: { "PROCESS_KEY" => "process" }).app("orders").env

    assert_equal [".env", "apps/orders/.env", "process", nil],
                 [env.source("SOLUTION_KEY"), env.source("PROJECT_KEY"), env.source("PROCESS_KEY"), env.source("NOPE")]
  end

  def test_source_of_a_key_is_the_winning_file_of_the_active_environment
    write(".env", "LAYERED=base\n")
    write(".env.local", "LAYERED=local\n")

    env = build_boot.app("orders", env_name: "development").env

    assert_equal [".env.local", "local"], [env.source("LAYERED"), env.fetch("LAYERED")]
  end

  def test_file_keys_include_keys_the_process_overrides_but_not_process_only_keys
    write(".env", "SHARED=solution\n")

    env = build_boot(env: { "SHARED" => "process", "PROCESS_ONLY" => "process" }).app("orders").env

    assert_equal "process", env.fetch("SHARED")
    assert_includes env.file_keys, "SHARED"
    refute_includes env.file_keys, "PROCESS_ONLY"
  end

  def test_app_env_is_the_project_env
    write("apps/orders/.env", "PROJECT_KEY=project\n")

    app = build_boot.app("orders")

    assert_equal "project", app.env.fetch("PROJECT_KEY")
  end

  private

  def build_boot(env: {}, ports: {})
    boot = Boto::Boot.new(Boto::Botofile.load(File.join(@root, "Botofile")), root: @root, env: env,
                                                                            ports: ports, warn_output: StringIO.new)
    @boots << boot
    boot
  end

  def write(relative_path, content)
    path = File.join(@root, relative_path)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, content)
  end
end
