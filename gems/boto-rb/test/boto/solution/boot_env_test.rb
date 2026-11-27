# frozen_string_literal: true

require "test_helper"
require "fileutils"
require "stringio"
require "tmpdir"

class Boto::BootEnvTest < Minitest::Test
  FIXTURE = File.expand_path("../../fixtures/environment", __dir__)

  def setup
    @root = Dir.mktmpdir("boto-dotenv")
    FileUtils.cp_r(File.join(FIXTURE, "."), @root)
    @boots = []
  end

  def teardown
    @boots.each(&:shutdown)
    FileUtils.remove_entry(@root)
  end

  def test_solution_env_reaches_the_process_without_overwriting_it
    write(".env", "SHARED=from-solution\nKEPT=from-solution\n")
    env = { "KEPT" => "from-process" }

    build_boot(env: env).app("orders")

    assert_equal "from-solution", env["SHARED"]
    assert_equal "from-process", env["KEPT"]
  end

  def test_project_env_stays_out_of_the_process
    write("apps/orders/.env", "DATABASE_URL=orders-db\n")
    env = {}

    build_boot(env: env).app("orders")

    refute env.key?("DATABASE_URL")
  end

  def test_precedence_is_process_then_project_then_solution
    write(".env", "LAYERED=solution\nPROJECT_OVER_SOLUTION=solution\nSOLUTION_ONLY=solution\n")
    write("apps/orders/.env", "LAYERED=project\nPROJECT_OVER_SOLUTION=project\n")

    build_boot(env: { "LAYERED" => "process" }).app("orders")
    env = Orders.app.env

    assert_equal ["process", "project", "solution"],
                 [env["LAYERED"], env["PROJECT_OVER_SOLUTION"], env["SOLUTION_ONLY"]]
  end

  # The dev reload boots again in the same process; a solution value written by the first boot must not win.
  def test_second_boot_with_the_process_snapshot_keeps_the_project_over_the_solution
    write(".env", "DATABASE_URL=solution-db\n")
    write("apps/orders/.env", "DATABASE_URL=orders-db\n")
    env = {}
    snapshot = env.dup

    build_boot(env: env).app("orders")
    assert_equal "solution-db", env["DATABASE_URL"]
    @boots.pop.shutdown
    build_boot(env: env, process_env: snapshot).app("orders")

    assert_equal "orders-db", Orders.app.env.fetch("DATABASE_URL")
  end

  def test_env_local_is_ignored_in_test
    write("apps/orders/.env.local", "LOCAL_ONLY=local\n")

    build_boot.app("orders", env_name: "test")

    refute Orders.app.env.key?("LOCAL_ONLY")
  end

  def test_env_local_is_read_outside_test
    write("apps/orders/.env.local", "LOCAL_ONLY=local\n")

    build_boot.app("orders", env_name: "development")

    assert_equal "local", Orders.app.env.fetch("LOCAL_ONLY")
  end

  def test_each_project_gets_its_own_database_url_in_the_same_process
    write("apps/orders/.env", "DATABASE_URL=orders-db\n")
    write("apps/pedidos/.env", "DATABASE_URL=pedidos-db\n")
    env = {}
    boot = build_boot(env: env)

    boot.app("orders")
    boot.app("pedidos")

    assert_equal "orders-db", Orders.app.env.fetch("DATABASE_URL")
    assert_equal "pedidos-db", Pedidos.app.env.fetch("DATABASE_URL")
    refute env.key?("DATABASE_URL")
  end

  def test_new_boot_refreshes_the_project_app
    write("apps/orders/.env", "FRONTEND_URL=first\n")
    first = build_boot
    first.app("orders")
    first.shutdown
    write("apps/orders/.env", "FRONTEND_URL=second\n")

    build_boot.app("orders")

    assert_equal "second", Orders.app.env.fetch("FRONTEND_URL")
  end

  private

  def build_boot(env: {}, process_env: nil)
    boot = Boto::Boot.new(Boto::Botofile.load(File.join(@root, "Botofile")), root: @root, env: env,
                                                                            process_env: process_env,
                                                                            warn_output: StringIO.new)
    @boots << boot
    boot
  end

  def write(relative_path, content)
    path = File.join(@root, relative_path)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, content)
  end
end
