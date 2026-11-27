# frozen_string_literal: true

require "test_helper"
require "fileutils"
require "rack/mock"
require "stringio"
require "tmpdir"

# Named outside Commands: any constant there is listed as a command by the runner.
class Boto::CLI::AddCommandTest < Minitest::Test
  def test_webapi_generates_endpoint_and_helper
    with_solution do |dir|
      out = StringIO.new
      assert_equal 0, add_command(%w[webapi api], cwd: dir, out: out).call

      %w[endpoints schemas test/endpoints test/schemas].each do |folder|
        assert File.file?(File.join(dir, "apps/api", folder, ".keep")), folder
      end
      refute File.exist?(File.join(dir, "apps/api/endpoints/health.rb"))
      refute File.exist?(File.join(dir, "apps/api/schemas/health_schema.rb"))
      assert_includes read(dir, "apps/api/test/test_helper.rb"), %(BOOT.app("api", env_name: "test"))
      assert_includes out.string, "create apps/api/test/config/health_test.rb"
      assert_includes out.string, "update Botofile"
    end
  end

  def test_webapi_generates_security_config_and_health_probes
    with_solution do |dir|
      add_command(%w[webapi api], cwd: dir).call

      app_config = read(dir, "apps/api/config/app.rb")
      assert_includes app_config, "app.use :auth"
      assert_includes app_config, "app.use :health"
      assert_includes read(dir, "apps/api/test/config/health_test.rb"), "/health/live"
    end
  end

  def test_webapi_generates_one_config_file_per_environment
    with_solution do |dir|
      add_command(%w[webapi api], cwd: dir).call

      %w[development test production].each do |env_name|
        assert File.file?(File.join(dir, "apps/api/config/environments", "#{env_name}.rb")), env_name
      end
    end
  end

  def test_webapi_app_config_reads_secrets_without_branches
    with_solution do |dir|
      add_command(%w[webapi api], cwd: dir).call

      app_config = read(dir, "apps/api/config/app.rb")
      assert_includes app_config, %(tokens: -> { app.env.fetch("API_TOKENS").split(",") })
      refute_includes app_config, "default_tokens"
      refute_match(/\bif\b/, app_config)
    end
  end

  def test_generated_api_boots_in_development_and_test_without_env_vars
    with_solution do |dir|
      add_command(%w[webapi api], cwd: dir).call
      write_ping(dir)

      { "development" => "dev-token", "test" => "test-token" }.each do |env_name, token|
        assert_token_accepted(dir, env_name: env_name, token: token)
      end
    end
  end

  def test_generated_api_in_production_fails_at_boot_without_api_tokens
    with_solution do |dir|
      add_command(%w[webapi api], cwd: dir).call

      error = assert_raises(KeyError) { with_api_app(dir, env_name: "production") { flunk "booted" } }
      assert_includes error.message, "API_TOKENS"
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

      assert_no_template_leftovers(File.join(dir, "apps", "api"))
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

  def test_library_creates_libs_folder_on_add
    with_solution do |dir|
      refute File.directory?(File.join(dir, "libs"))

      add_command(%w[library dominio], cwd: dir).call

      assert File.directory?(File.join(dir, "libs/dominio"))
    end
  end

  def test_underscored_name_gets_camel_case_namespace
    with_solution do |dir|
      add_command(%w[webapi order_items], cwd: dir).call

      assert_includes read(dir, "apps/order_items/test/config/health_test.rb"), "class OrderItemsHealthTest"
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
      FileUtils.mkdir_p(File.join(dir, "apps", "api"))

      error = assert_raises(Boto::CLI::Error) { add_command(%w[webapi api], cwd: dir).call }
      assert_equal %(directory "apps/api" already exists), error.message
    end
  end

  def test_missing_arguments_raise_usage
    with_solution do |dir|
      [[], ["webapi"]].each do |argv|
        error = assert_raises(Boto::CLI::Error) { add_command(argv, cwd: dir).call }
        assert_equal "Usage: boto add <webapi|library> <name>", error.message
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

  # Boots the generated api with an empty env, so the test never reads or writes the real ENV.
  def with_api_app(dir, env_name:)
    boot = Boto::Boot.new(Boto::Botofile.load(File.join(dir, "Botofile")),
                          root: dir, env: {}, warn_output: StringIO.new)
    yield boot.app("api", env_name: env_name)
  ensure
    boot&.shutdown
  end

  def assert_token_accepted(dir, env_name:, token:)
    with_api_app(dir, env_name: env_name) do |app|
      request = Rack::MockRequest.new(app)
      assert_equal 200, request.get("/ping", "HTTP_AUTHORIZATION" => "Bearer #{token}").status, env_name
      assert_equal 401, request.get("/ping", "HTTP_AUTHORIZATION" => "Bearer wrong").status, env_name
    end
  end

  def write_ping(dir)
    File.write(File.join(dir, "apps/api/endpoints/ping.rb"), <<~RUBY)
      # frozen_string_literal: true

      class Api::Ping < Boto::Endpoint
        get "/ping"

        def call = { ok: true }
      end
    RUBY
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
