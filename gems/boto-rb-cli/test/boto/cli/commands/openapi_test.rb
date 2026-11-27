# frozen_string_literal: true

require "test_helper"
require "fileutils"
require "json"
require "stringio"
require "support/fake_template_gem"
require "tmpdir"

# Named outside Commands: any constant there is listed as a command by the runner.
class Boto::CLI::OpenapiCommandTest < Minitest::Test
  SOLUTION_NAME = "docs"
  WEBAPI = "docapi"
  LIBRARY = "doclib"
  OUTPUT_FILE = "openapi.json"

  # Booting loads the projects with Zeitwerk, so the shared solution is built once for this class.
  def self.solution_dir
    @solution_dir ||= create_solution(Dir.mktmpdir)
                      .tap { |dir| Minitest.after_run { FileUtils.remove_entry(File.dirname(dir)) } }
  end

  def self.create_solution(root)
    quiet = { out: StringIO.new, err: StringIO.new }
    Boto::CLI::Commands::New.new([SOLUTION_NAME], cwd: root, **quiet).call
    dir = File.join(root, SOLUTION_NAME)
    Boto::CLI::Commands::Add.new(["webapi", WEBAPI], cwd: dir, **quiet).call
    Boto::CLI::Commands::Add.new(["library", LIBRARY], cwd: dir, **quiet).call
    dir
  end

  def teardown
    FileUtils.rm_f(File.join(self.class.solution_dir, OUTPUT_FILE))
  end

  def test_unwritable_output_is_a_usage_error
    error = assert_raises(Boto::CLI::Error) { run_command(["docapi", "-o", "missing_dir/openapi.json"]) }
    assert_includes error.message, "cannot write missing_dir/openapi.json"
  end

  def test_prints_the_openapi_document_as_json
    out = StringIO.new
    assert_equal 0, run_command([WEBAPI], out: out)

    document = JSON.parse(out.string)
    assert_equal "3.1.0", document["openapi"]
    assert_equal WEBAPI, document.dig("info", "title")
    assert_equal "0.1.0", document.dig("info", "version")
    assert_empty document["paths"]
  end

  def test_api_version_option_sets_the_info_version
    out = StringIO.new
    assert_equal 0, run_command([WEBAPI, "--api-version", "2.0.0"], out: out)

    assert_equal "2.0.0", JSON.parse(out.string).dig("info", "version")
  end

  def test_output_option_writes_the_file_relative_to_cwd
    out = StringIO.new
    assert_equal 0, run_command([WEBAPI, "-o", OUTPUT_FILE], out: out)

    assert_equal "write #{OUTPUT_FILE}\n", out.string
    document = JSON.parse(File.read(File.join(self.class.solution_dir, OUTPUT_FILE)))
    assert_equal WEBAPI, document.dig("info", "title")
  end

  def test_library_project_has_no_endpoints
    error = assert_raises(Boto::CLI::Error) { run_command([LIBRARY]) }
    assert_equal %(project "#{LIBRARY}" (library) has no endpoints), error.message
  end

  def test_unknown_project_raises
    error = assert_raises(Boto::CLI::Error) { run_command(["ghost"]) }
    assert_equal %(unknown project "ghost"), error.message
  end

  def test_missing_project_raises_usage
    error = assert_raises(Boto::CLI::Error) { run_command([]) }
    assert_equal Boto::CLI::Commands::Openapi::USAGE, error.message
  end

  def test_invalid_option_raises
    error = assert_raises(Boto::CLI::Error) { run_command(["--bogus"]) }
    assert_includes error.message, "--bogus"
  end

  def test_http_gem_template_is_documented
    with_gem_project(http: true) do |dir|
      out = StringIO.new
      assert_equal 0, run_command(["gemdoc"], out: out, cwd: dir)

      assert_equal "gemdoc", JSON.parse(out.string).dig("info", "title")
    end
  end

  def test_non_http_gem_template_has_no_endpoints
    with_gem_project(http: false) do |dir|
      error = assert_raises(Boto::CLI::Error) { run_command(["gemdoc"], cwd: dir) }
      assert_equal %(project "gemdoc" (gemjobs) has no endpoints), error.message
    end
  end

  def test_runner_help_lists_the_command
    out = StringIO.new
    Boto::CLI::Runner.new(out: out, err: StringIO.new, cwd: self.class.solution_dir).run(["help"])

    assert_match(/^  openapi +#{Regexp.escape(Boto::CLI::Commands::Openapi::SUMMARY)}$/, out.string)
  end

  private

  def run_command(argv, out: StringIO.new, cwd: self.class.solution_dir)
    Boto::CLI::Commands::Openapi.new(argv, out: out, err: StringIO.new, cwd: cwd).call
  end

  # A fresh solution with one project from a fake gem template ("gemjobs" when not http), named "gemdoc".
  def with_gem_project(http:)
    template = http ? "gemweb" : "gemjobs"
    template_gem = FakeTemplateGem.new
    template_gem.declare(template, http: http, files: Boto::CLI::Generator.official_dir("webapi"))
    template_gem.activate
    Dir.mktmpdir do |root|
      dir = self.class.create_solution(root)
      Boto::CLI::Commands::Add.new([template, "gemdoc"], cwd: dir, out: StringIO.new, err: StringIO.new).call
      yield dir
    end
  ensure
    template_gem&.cleanup
  end
end
