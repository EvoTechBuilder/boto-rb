# frozen_string_literal: true

require "test_helper"
require "fileutils"
require "rbconfig"
require "stringio"
require "tmpdir"
require "sequel"
require "boto/database"

# Named outside Commands: any constant there is listed as a command by the runner.
class Boto::CLI::TestCommandTest < Minitest::Test
  SOURCE = <<~BOTO
    solution "shop"
    project "domain", template: :library
    project "orders", template: :webapi, refs: ["domain"]
    project "billing", template: :webapi, refs: ["orders"]
    project "tools", template: :library
  BOTO
  TESTED_PATHS = %w[libs/domain apps/billing].freeze

  def setup
    @calls = []
    @changed_calls = []
  end

  def test_runs_projects_with_tests_in_topological_order
    with_solution do |cwd|
      out = StringIO.new
      assert_equal 0, build_command([], cwd: cwd, out: out).call
      assert_equal [File.join(cwd, "libs/domain"), File.join(cwd, "apps/billing")], chdirs
      assert_includes out.string, "-- skip orders (no test/)"
      assert_includes out.string, "== domain"
      assert_includes out.string, "2 projects tested, 0 failed"
    end
  end

  def test_runs_only_the_named_project
    with_solution do |cwd|
      out = StringIO.new
      assert_equal 0, build_command(["billing"], cwd: cwd, out: out).call
      assert_equal [File.join(cwd, "apps/billing")], chdirs
      refute_includes out.string, "== domain"
    end
  end

  def test_affected_uses_default_base_main
    with_solution do |cwd|
      assert_equal 0, build_command(["--affected"], cwd: cwd, changed: ["libs/domain/lib/a.rb"]).call
      assert_equal [["main", cwd]], @changed_calls
      assert_equal [File.join(cwd, "libs/domain"), File.join(cwd, "apps/billing")], chdirs
    end
  end

  def test_base_option_is_passed_to_changed_files
    with_solution do |cwd|
      build_command(["--affected", "--base", "dev"], cwd: cwd, changed: ["libs/domain/lib/a.rb"]).call
      assert_equal [["dev", cwd]], @changed_calls
    end
  end

  def test_failed_project_returns_failure_and_is_listed
    with_solution do |cwd|
      out = StringIO.new
      status = build_command([], cwd: cwd, out: out, failing: ["billing"]).call
      assert_equal 1, status
      assert_includes out.string, "2 projects tested, 1 failed"
      assert_includes out.string, "failed: billing"
    end
  end

  def test_unknown_project_raises
    with_solution do |cwd|
      error = assert_raises(Boto::CLI::Error) { build_command(["nope"], cwd: cwd).call }
      assert_equal %(unknown project "nope"), error.message
    end
  end

  def test_invalid_option_raises
    with_solution do |cwd|
      error = assert_raises(Boto::CLI::Error) { build_command(["--wat"], cwd: cwd).call }
      assert_match(/invalid option: --wat/, error.message)
    end
  end

  def test_project_with_affected_raises
    with_solution do |cwd|
      error = assert_raises(Boto::CLI::Error) { build_command(["billing", "--affected"], cwd: cwd).call }
      assert_equal "a project cannot be combined with --affected", error.message
    end
  end

  def test_no_selected_projects_reports_and_succeeds
    with_solution do |cwd|
      out = StringIO.new
      status = build_command(["--affected"], cwd: cwd, out: out, changed: ["README.md"]).call
      assert_equal 0, status
      assert_equal "no projects to test\n", out.string
      assert_empty @calls
    end
  end

  def test_runs_ruby_with_loader_in_project_dir
    with_solution do |cwd|
      build_command(["domain"], cwd: cwd).call
      command, chdir = @calls.first
      assert_equal [RbConfig.ruby, "-Itest", "-e", Boto::CLI::Commands::Test::TEST_LOADER], command
      assert_equal File.join(cwd, "libs/domain"), chdir
    end
  end

  def test_default_changed_files_raises_outside_git_repo
    Dir.mktmpdir do |cwd|
      error = assert_raises(Boto::CLI::Error) do
        Boto::CLI::Commands::Test::DEFAULT_CHANGED_FILES.call("main", cwd)
      end
      assert_match(/git failed/, error.message)
    end
  end


  def test_summary_uses_singular_for_one_project
    command = Boto::CLI::Commands::Test.new([], out: out = StringIO.new, err: StringIO.new, cwd: Dir.pwd)
    command.send(:report, 1, [])

    assert_equal "1 project tested, 0 failed\n", out.string
  end

  def test_migrates_the_test_database_before_its_tests_run
    with_solution do |cwd|
      use_test_database(cwd, "billing")
      out = StringIO.new
      tables_at_run = []
      observe = ->(_chdir) { tables_at_run << database_tables(cwd) }
      build_command(["billing"], cwd: cwd, out: out, observe: observe).call

      assert_includes out.string, "billing: migrated 20260101000000_create_things.rb\n"
      assert_equal [[:things]], tables_at_run
    end
  end

  def test_without_the_database_gem_tests_run_and_nothing_is_migrated
    with_solution do |cwd|
      use_test_database(cwd, "billing")
      out = StringIO.new
      missing = -> { raise LoadError, "cannot load such file -- boto/database" }
      status = build_command(["billing"], cwd: cwd, out: out, database_library: missing).call

      assert_equal 0, status
      refute_includes out.string, "migrated"
      assert_equal [File.join(cwd, "apps/billing")], chdirs
    end
  end

  def test_project_without_database_runs_its_tests_without_migrating
    with_solution do |cwd|
      out = StringIO.new
      assert_equal 0, build_command(["billing"], cwd: cwd, out: out).call

      refute_includes out.string, "migrated"
      assert_equal [File.join(cwd, "apps/billing")], chdirs
    end
  end

  private

  def chdirs
    @calls.map(&:last)
  end

  # The test environment declares the database; the migration creates one table in it.
  def use_test_database(cwd, project)
    project_dir = File.join(cwd, "apps", project)
    FileUtils.mkdir_p(File.join(project_dir, "config", "environments"))
    FileUtils.mkdir_p(File.join(project_dir, "db", "migrations"))
    File.write(File.join(project_dir, "config", "environments", "test.rb"), <<~RUBY)
      Boto.configure do |app|
        app.use :database, url: "sqlite://#{cwd}/test.sqlite3"
      end
    RUBY
    File.write(File.join(project_dir, "db", "migrations", "20260101000000_create_things.rb"), <<~RUBY)
      Sequel.migration do
        change do
          create_table(:things) { primary_key :id }
        end
      end
    RUBY
  end

  def database_tables(cwd)
    database = Sequel.sqlite(File.join(cwd, "test.sqlite3"))
    database.tables - [:schema_migrations]
  ensure
    database&.disconnect
  end

  def with_solution
    Dir.mktmpdir do |cwd|
      File.write(File.join(cwd, "Botofile"), SOURCE)
      TESTED_PATHS.each { |path| FileUtils.mkdir_p(File.join(cwd, path, "test")) }
      yield cwd
    end
  end

  def build_command(argv, cwd:, out: StringIO.new, failing: [], changed: [], observe: nil,
                    database_library: -> {})
    Boto::CLI::Commands::Test.new(
      argv, out: out, err: StringIO.new, cwd: cwd,
      process_runner: process_runner(failing, observe), changed_files: changed_files(changed),
      env: { "API_TOKENS" => "test-token" }, database_library: database_library
    )
  end

  # observe runs when the tests would start, so a test can check what the migration already did.
  def process_runner(failing, observe)
    lambda do |command, chdir:|
      @calls << [command, chdir]
      observe&.call(chdir)
      !failing.include?(File.basename(chdir))
    end
  end

  def changed_files(changed)
    lambda do |base, cwd|
      @changed_calls << [base, cwd]
      changed
    end
  end
end
