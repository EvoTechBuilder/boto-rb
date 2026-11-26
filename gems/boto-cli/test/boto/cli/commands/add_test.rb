# frozen_string_literal: true

require "test_helper"
require "fileutils"
require "stringio"
require "tmpdir"

# Named outside Commands: any constant there is listed as a command by the runner.
class Boto::CLI::AddCommandTest < Minitest::Test
  def test_webapi_generates_endpoint_and_helper
    with_solution do |dir|
      out = StringIO.new
      assert_equal 0, add_command(%w[webapi api], cwd: dir, out: out).call

      assert_includes read(dir, "services/api/endpoints/health.rb"), "class Api::Health < Boto::Endpoint"
      assert_includes read(dir, "services/api/endpoints/health.rb"), "returns Api::HealthSchema"
      assert_includes read(dir, "services/api/schemas/health_schema.rb"), "class Api::HealthSchema < Boto::Schema"
      assert File.file?(File.join(dir, "services/api/test/schemas/health_schema_test.rb"))
      assert_includes read(dir, "services/api/test/test_helper.rb"), %(BOOT.app("api"))
      assert_includes out.string, "create services/api/endpoints/health.rb"
      assert_includes out.string, "update Botofile"
    end
  end

  def test_webapi_generates_security_config_and_public_health
    with_solution do |dir|
      add_command(%w[webapi api], cwd: dir).call

      assert_includes read(dir, "services/api/config/app.rb"), "app.use :auth"
      assert_includes read(dir, "services/api/endpoints/health.rb"), "skip :auth, :rate_limit"
    end
  end

  def test_webapi_declares_project_in_botofile
    with_solution do |dir|
      add_command(%w[webapi api], cwd: dir).call

      assert_equal %w[api], projects(dir)
    end
  end

  def test_webapi_generates_no_template_leftovers
    with_solution do |dir|
      add_command(%w[webapi api], cwd: dir).call

      assert_no_template_leftovers(File.join(dir, "services", "api"))
    end
  end

  def test_library_generates_keep_files_and_helper
    with_solution do |dir|
      add_command(%w[library domain], cwd: dir).call

      assert File.file?(File.join(dir, "libs/domain/operations/.keep"))
      assert File.file?(File.join(dir, "libs/domain/models/.keep"))
      assert File.file?(File.join(dir, "libs/domain/schemas/.keep"))
      helper = read(dir, "libs/domain/test/test_helper.rb")
      assert_includes helper, %(BOOT.load("domain"))
      refute_includes helper, "rack/mock"
      assert_no_template_leftovers(File.join(dir, "libs", "domain"))
    end
  end

  def test_underscored_name_gets_camel_case_namespace
    with_solution do |dir|
      add_command(%w[webapi order_items], cwd: dir).call

      assert_includes read(dir, "services/order_items/endpoints/health.rb"), "class OrderItems::Health"
    end
  end

  def test_unknown_template_raises
    with_solution do |dir|
      error = assert_raises(Boto::CLI::Error) { add_command(%w[worker x], cwd: dir).call }
      assert_equal %(unknown template "worker" (available: webapi, library)), error.message
    end
  end

  def test_invalid_name_raises
    with_solution do |dir|
      ["Api", "1api", "../x", ""].each do |name|
        error = assert_raises(Boto::CLI::Error) { add_command(["webapi", name], cwd: dir).call }
        assert_equal %(invalid project name "#{name}"), error.message
      end
    end
  end

  def test_duplicate_project_raises
    with_solution do |dir|
      add_command(%w[webapi api], cwd: dir).call

      error = assert_raises(Boto::CLI::Error) { add_command(%w[library api], cwd: dir).call }
      assert_equal %(project "api" already exists), error.message
    end
  end

  def test_existing_target_directory_raises
    with_solution do |dir|
      FileUtils.mkdir_p(File.join(dir, "services", "api"))

      error = assert_raises(Boto::CLI::Error) { add_command(%w[webapi api], cwd: dir).call }
      assert_equal %(directory "services/api" already exists), error.message
    end
  end

  def test_missing_arguments_raise_usage
    with_solution do |dir|
      [[], ["webapi"]].each do |argv|
        error = assert_raises(Boto::CLI::Error) { add_command(argv, cwd: dir).call }
        assert_equal "usage: boto add <webapi|library> <name>", error.message
      end
    end
  end

  def test_missing_botofile_raises
    Dir.mktmpdir do |dir|
      assert_raises(Boto::CLI::Error) { add_command(%w[webapi api], cwd: dir).call }
    end
  end

  def test_botofile_without_final_newline_stays_valid
    with_solution do |dir|
      File.write(File.join(dir, "Botofile"), %(solution "shop"))

      add_command(%w[webapi api], cwd: dir).call

      assert_equal %w[api], projects(dir)
    end
  end

  private

  def with_solution
    Dir.mktmpdir do |tmp|
      Boto::CLI::Commands::New.new(["shop"], out: StringIO.new, err: StringIO.new, cwd: tmp).call
      yield File.join(tmp, "shop")
    end
  end

  def add_command(argv, cwd:, out: StringIO.new)
    Boto::CLI::Commands::Add.new(argv, out: out, err: StringIO.new, cwd: cwd)
  end

  def read(dir, relative)
    File.read(File.join(dir, relative))
  end

  def projects(dir)
    Boto::Botofile.load(File.join(dir, "Botofile")).projects.map(&:name)
  end

  def assert_no_template_leftovers(project_dir)
    leftovers = Dir.glob("**/*", base: project_dir).select do |path|
      path.end_with?(".erb")
    end
    assert_empty leftovers
  end
end
