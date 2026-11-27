# frozen_string_literal: true

require "test_helper"
require "fileutils"
require "open3"
require "rbconfig"
require "stringio"
require "tmpdir"

# Named outside Commands: any constant there is listed as a command by the runner.
class Boto::CLI::PluginCommandTest < Minitest::Test
  ROOT_GEMFILE = File.expand_path("../../../../../../Gemfile", __dir__)
  LOAD_TESTS = 'Dir[File.join(ARGV[0], "test/**/*_test.rb")].sort.each { |file| require file }'
  BASE_FILES = %w[
    .gitignore CHANGELOG.md Gemfile LICENSE README.md Rakefile boto-rb-gateway.gemspec
    lib/boto/gateway.rb lib/boto/gateway/version.rb test/test_helper.rb
  ].freeze

  def setup
    @cwd = Dir.mktmpdir
    @out = StringIO.new
    @err = StringIO.new
  end

  def teardown
    FileUtils.remove_entry(@cwd)
  end

  def test_base_gem_has_only_the_base_files
    generate("boto-rb-gateway")

    assert_equal BASE_FILES, files_of("boto-rb-gateway")
  end

  def test_gemspec_depends_on_the_cli_minor_version
    generate("boto-rb-gateway")

    minor = Boto::CLI::VERSION.split(".").first(2).join(".")
    assert_includes read("boto-rb-gateway", "boto-rb-gateway.gemspec"), %(spec.add_dependency "boto-rb", "~> #{minor}.0")
  end

  def test_entry_file_ignores_templates_and_declares_the_module
    generate("boto-rb-gateway")

    entry = read("boto-rb-gateway", "lib/boto/gateway.rb")
    assert_includes entry, %(loader.ignore("\#{__dir__}/templates"))
    assert_includes entry, "module Gateway"
    refute_includes entry, "only requires this file"
  end

  def test_plugin_creates_the_plugin_and_its_flunking_test
    generate("boto-rb-gateway", "--plugin", "gateway")

    assert_includes files_of("boto-rb-gateway"), "lib/boto/plugins/gateway.rb"
    assert_includes files_of("boto-rb-gateway"), "test/boto/plugins/gateway_test.rb"
    assert_includes read("boto-rb-gateway", "lib/boto/plugins/gateway.rb"), "class Gateway < Boto::Plugin"
    assert_includes read("boto-rb-gateway", "lib/boto/plugins/gateway.rb"), "app.call(env)"
    assert_includes read("boto-rb-gateway", "test/boto/plugins/gateway_test.rb"),
                    %(flunk "test Boto::Plugins::Gateway: write the plugin's tests")
  end

  def test_plugin_with_the_extension_name_needs_no_shim
    generate("boto-rb-gateway", "--plugin", "gateway")

    expected = (BASE_FILES + %w[lib/boto/plugins/gateway.rb test/boto/plugins/gateway_test.rb]).sort

    assert_equal expected, files_of("boto-rb-gateway")
  end

  def test_template_defaults_to_apps_without_http
    generate("boto-rb-gateway", "--template", "gateway")

    template = read("boto-rb-gateway", "lib/boto/templates/gateway/template.rb")
    assert_includes template, %(t.folder "apps")
    assert_includes template, "t.http false"
    assert_includes files_of("boto-rb-gateway"), "lib/boto/templates/gateway/files/config/app.rb.erb"
    assert_includes files_of("boto-rb-gateway"), "test/boto/templates/gateway_test.rb"
  end

  def test_template_with_http_and_folder
    generate("boto-rb-gateway", "--template", "gateway", "--http", "--folder", "libs")

    template = read("boto-rb-gateway", "lib/boto/templates/gateway/template.rb")
    assert_includes template, %(t.folder "libs")
    assert_includes template, "t.http true"
  end

  def test_template_config_keeps_namespace_for_the_solution_to_render
    generate("boto-rb-gateway", "--template", "gateway")

    config = read("boto-rb-gateway", "lib/boto/templates/gateway/files/config/app.rb.erb")
    assert_includes config, "# Plugins for <%= namespace %>, for every environment."
    assert_includes config, "Boto.configure do |app|"
  end

  def test_plugin_and_template_together
    generate("boto-rb-gateway", "--plugin", "gateway", "--template", "gateway")

    assert_includes files_of("boto-rb-gateway"), "lib/boto/plugins/gateway.rb"
    assert_includes files_of("boto-rb-gateway"), "lib/boto/templates/gateway/template.rb"
  end

  def test_plugin_named_differently_gets_a_shim_and_an_ignore
    generate("acme-boto-audit", "--plugin", "audit")

    assert_equal %(require "boto/acme_boto_audit"\n), read("acme-boto-audit", "lib/boto/audit.rb").lines.last
    entry = read("acme-boto-audit", "lib/boto/acme_boto_audit.rb")
    assert_includes entry, %(loader.ignore("\#{__dir__}/audit.rb"))
    assert_includes files_of("acme-boto-audit"), "lib/boto/plugins/audit.rb"
    assert_includes files_of("acme-boto-audit"), "test/boto/plugins/audit_test.rb"
  end

  def test_name_overrides_the_extension
    generate("boto-rb-gateway", "--name", "gw")

    assert_includes files_of("boto-rb-gateway"), "lib/boto/gw.rb"
    assert_includes read("boto-rb-gateway", "lib/boto/gw/version.rb"), "module Gw"
  end

  def test_readme_only_documents_what_was_generated
    generate("boto-rb-gateway")
    refute_includes read("boto-rb-gateway", "README.md"), "## Plugin"

    generate("boto-rb-other", "--plugin", "gateway", "--template", "gateway", "--http")
    readme = read("boto-rb-other", "README.md")
    assert_includes readme, "app.use :gateway"
    assert_includes readme, "boto add gateway <name>"
    assert_includes readme, "as an HTTP project"
  end

  def test_license_uses_the_given_year
    generate("boto-rb-gateway")

    assert_includes read("boto-rb-gateway", "LICENSE"), "Copyright (c) 2026 TODO"
  end

  def test_prints_each_file_and_the_next_step
    generate("boto-rb-gateway", "--plugin", "gateway")

    assert_includes @out.string, "create boto-rb-gateway/Gemfile\n"
    assert_includes @out.string, "create boto-rb-gateway/lib/boto/plugins/gateway.rb\n"
    assert_includes @out.string, "Next: cd boto-rb-gateway && bundle install && bundle exec rake test\n"
  end

  def test_works_inside_a_solution_folder
    Dir.mkdir(File.join(@cwd, "loja"))
    Dir.mkdir(File.join(@cwd, "loja", "apps"))

    assert_equal 0, Boto::CLI::Commands::Plugin.new(%w[new boto-rb-gateway], out: @out, err: @err,
                                                                           cwd: File.join(@cwd, "loja")).call
    assert Dir.exist?(File.join(@cwd, "loja", "boto-rb-gateway", "lib"))
  end

  def test_invalid_gem_name_raises_and_writes_nothing
    error = assert_raises(Boto::CLI::Error) { run_command(%w[new Boto-rb-gateway]) }

    assert_equal %(invalid gem name "Boto-rb-gateway"), error.message
    assert_empty Dir.children(@cwd)
  end

  def test_invalid_plugin_and_template_names_raise
    error = assert_raises(Boto::CLI::Error) { run_command(%w[new boto-rb-gateway --plugin Gate]) }
    assert_match(/\Ainvalid plugin name "Gate"/, error.message)

    error = assert_raises(Boto::CLI::Error) { run_command(%w[new boto-rb-gateway --template 1gate]) }
    assert_match(/\Ainvalid template name "1gate"/, error.message)
  end

  def test_folder_must_be_apps_libs_or_workers
    error = assert_raises(Boto::CLI::Error) { run_command(%w[new boto-rb-gateway --template gateway --folder src]) }

    assert_equal %(folder must be one of apps, libs, workers, got "src"), error.message
    assert_empty Dir.children(@cwd)
  end

  def test_http_and_folder_need_a_template
    error = assert_raises(Boto::CLI::Error) { run_command(%w[new boto-rb-gateway --http]) }
    assert_equal "--http and --folder only apply with --template", error.message

    assert_raises(Boto::CLI::Error) { run_command(%w[new boto-rb-gateway --folder libs]) }
  end

  def test_existing_directory_raises
    Dir.mkdir(File.join(@cwd, "boto-rb-gateway"))

    error = assert_raises(Boto::CLI::Error) { run_command(%w[new boto-rb-gateway]) }
    assert_equal %(directory "boto-rb-gateway" already exists), error.message
  end

  def test_usage_errors
    [[], %w[new], %w[new a b], %w[build boto-rb-gateway]].each do |argv|
      error = assert_raises(Boto::CLI::Error) { run_command(argv) }
      assert_equal Boto::CLI::Commands::Plugin::USAGE, error.message, argv.inspect
    end
  end

  def test_reserved_plugin_name_warns_but_creates_the_gem
    assert_equal 0, run_command(%w[new boto-rb-gateway --plugin health])

    assert_includes @err.string, %(warning: plugin name "health" is reserved)
    assert_includes files_of("boto-rb-gateway"), "lib/boto/plugins/health.rb"
  end

  def test_official_template_name_warns
    run_command(%w[new boto-rb-gateway --template webapi])

    assert_includes @err.string, %(warning: template name "webapi" is reserved)
  end

  def test_generated_gem_runs_its_tests_with_the_plugin_still_flunking
    gem_dir = generate("boto-demo", "--plugin", "demo", "--template", "demo", "--http")

    out, _err, status = ruby_with_root_bundle("-I#{gem_dir}/lib", "-I#{gem_dir}/test", "-e", LOAD_TESTS, gem_dir)

    refute status.success?
    assert_match(/2 runs, \d+ assertions, 1 failures, 0 errors/, out)
    assert_includes out, "test Boto::Plugins::Demo: write the plugin's tests"
  end

  def test_generated_gem_loads_through_app_use_and_the_registry
    gem_dir = generate("boto-demo", "--plugin", "demo", "--template", "demo", "--http")
    script = <<~RUBY
      require "boto"
      config = Boto::Configuration.new(env_name: "test")
      config.use(:demo)
      puts config.plugin(:demo).class
      puts Boto::Templates.fetch(:demo).http
    RUBY

    out, err, status = ruby_with_root_bundle("-I#{gem_dir}/lib", "-e", script)

    assert status.success?, err
    assert_equal ["Boto::Plugins::Demo", "true"], out.lines.map(&:chomp)
  end

  private

  def run_command(argv)
    Boto::CLI::Commands::Plugin.new(argv, out: @out, err: @err, cwd: @cwd, year: 2026).call
  end

  # Returns the gem's folder, so the integration tests can point at it.
  def generate(gem_name, *options)
    run_command(["new", gem_name, *options])
    File.join(@cwd, gem_name)
  end

  def read(gem_name, relative)
    File.read(File.join(@cwd, gem_name, relative))
  end

  def files_of(gem_name)
    root = File.join(@cwd, gem_name)
    Dir.glob("**/*", File::FNM_DOTMATCH, base: root)
       .reject { |relative| File.directory?(File.join(root, relative)) }
       .sort
  end

  # A child process, so the generated gem's Zeitwerk setup and the template registry stay out of this process.
  def ruby_with_root_bundle(*args)
    Open3.capture3({ "BUNDLE_GEMFILE" => ROOT_GEMFILE }, RbConfig.ruby, *args)
  end
end
