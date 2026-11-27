# frozen_string_literal: true

require "test_helper"
require "fileutils"
require "json"
require "rack/mock"
require "stringio"
require "tmpdir"

class Boto::CLI::ReloaderTest < Minitest::Test
  SOLUTION_NAME = "shop"
  BOTOFILE_NAME = "Botofile"
  API = "api"
  PORT = 3000
  ENV_NAME = "development"
  AUTH = { "HTTP_AUTHORIZATION" => "Bearer dev-token" }.freeze
  EXTRA_PROJECT = %(project "extra", template: :webapi\n)
  GEMFILE_MESSAGE = "Gemfile changed: restart boto run"
  BOTOFILE_MESSAGE = "Botofile changed: restart boto run"
  SOLUTION_ENV_MESSAGE = ".env changed: restart boto run"
  ENV_KEY = "BOTO_RELOADER_TEST_VALUE"
  ZERO_CLOCK = -> { 0 }

  # One-shot like FileWatcher: changed? is true once per change.
  class FakeWatcher
    attr_reader :changes

    def initialize
      @pending = false
      @changes = 0
    end

    def touch(changes: 1)
      @pending = true
      @changes = changes
    end

    def changed?
      pending, @pending = @pending, false
      pending
    end
  end

  # Records the lifecycle of the plugin declared in the solution's config/app.rb.
  class Recorder < Boto::Plugin
    EVENTS = []

    def call(env, app) = app.call(env)
    def start = EVENTS << :start
    def stop = EVENTS << :stop
  end

  def setup
    @root = Dir.mktmpdir
    @dir = create_solution(@root)
    write_ping(ping_source(1))
    @out = StringIO.new
    @err = StringIO.new
    @watcher = FakeWatcher.new
  end

  def teardown
    @reloader&.shutdown
    FileUtils.remove_entry(@root)
  end

  def test_without_changes_the_same_app_is_served
    build_reloader

    assert_same @reloader.current(PORT), @reloader.current(PORT)
    assert_empty @out.string
  end

  def test_changed_endpoint_is_served_after_reload
    build_reloader
    assert_equal 1, ping_version

    write_ping(ping_source(2))
    @watcher.touch

    assert_equal 2, ping_version
    assert_includes @out.string, "Reloaded in 0 ms (1 file changed)"
  end

  def test_syntax_error_responds_500_until_the_file_is_fixed
    build_reloader
    write_ping("class Api::Ping < Boto::Endpoint\n  def call = { v: 1\nend\n")
    @watcher.touch

    response = get_ping
    assert_equal 500, response.status
    assert_equal "application/problem+json", response.headers["content-type"]
    problem = JSON.parse(response.body)
    assert_equal "Reload failed", problem["title"]
    assert_includes problem["detail"], "SyntaxError"
    assert_match(/Reload failed: \S*SyntaxError/, @err.string)

    write_ping(ping_source(1))
    @watcher.touch
    assert_equal 200, get_ping.status
  end

  def test_plugins_of_the_old_app_are_stopped_on_reload
    Recorder::EVENTS.clear
    declare_recorder
    build_reloader

    write_ping(ping_source(2))
    @watcher.touch
    get_ping

    assert_equal %i[start stop start], Recorder::EVENTS
  end

  def test_gemfile_change_warns_once_and_does_not_reload
    gemfile = FakeWatcher.new
    build_reloader(manifest_watchers: { "Gemfile" => gemfile })
    app = @reloader.current(PORT)

    gemfile.touch
    assert_same app, @reloader.current(PORT)
    assert_same app, @reloader.current(PORT)

    assert_equal 1, @err.string.scan(GEMFILE_MESSAGE).size
    refute_includes @out.string, "Reloaded"
  end

  def test_botofile_adding_a_project_warns_once_and_does_not_reload
    botofile = FakeWatcher.new
    build_reloader(manifest_watchers: { "Botofile" => botofile })
    app = @reloader.current(PORT)

    File.write(File.join(@dir, BOTOFILE_NAME), EXTRA_PROJECT, mode: "a")
    botofile.touch
    assert_same app, @reloader.current(PORT)
    assert_same app, @reloader.current(PORT)

    assert_equal 1, @err.string.scan(BOTOFILE_MESSAGE).size
    refute_includes @out.string, "Reloaded"
  end

  def test_changes_after_drain_do_not_reload
    build_reloader
    app = @reloader.current(PORT)
    @reloader.drain!

    write_ping(ping_source(2))
    @watcher.touch

    assert_same app, @reloader.current(PORT)
    refute_includes @out.string, "Reloaded"
  end

  def test_changed_project_env_is_seen_after_reload
    write_ping(env_ping_source)
    write_env_file(File.join(@dir, "apps", API, ".env"), "one")
    build_reloader
    assert_equal "one", ping_value

    write_env_file(File.join(@dir, "apps", API, ".env"), "two")
    @watcher.touch

    assert_equal "two", ping_value
  end

  def test_reload_keeps_process_values_over_solution_env_values
    write_ping(env_ping_source)
    write_env_file(File.join(@dir, ".env"), "solution")
    write_env_file(File.join(@dir, "apps", API, ".env"), "project")

    with_env_key_restored do
      build_reloader(process_env: {})
      assert_equal "project", ping_value

      @watcher.touch
      assert_equal "project", ping_value
    end
  end

  def test_solution_env_change_warns_once_and_does_not_reload
    env_watcher = FakeWatcher.new
    build_reloader(manifest_watchers: { Boto::CLI::Reloader::SOLUTION_ENV => env_watcher })
    app = @reloader.current(PORT)

    env_watcher.touch
    assert_same app, @reloader.current(PORT)
    assert_same app, @reloader.current(PORT)

    assert_equal 1, @err.string.scan(SOLUTION_ENV_MESSAGE).size
    refute_includes @out.string, "Reloaded"
  end

  private

  # Solution .env values are written to the real ENV at boot, so the key is restored after the test.
  def with_env_key_restored
    previous = ENV.fetch(ENV_KEY, nil)
    yield
  ensure
    if previous.nil?
      ENV.delete(ENV_KEY)
    else
      ENV[ENV_KEY] = previous
    end
  end

  def write_env_file(path, value)
    File.write(path, "#{ENV_KEY}=#{value}\n")
  end

  def env_ping_source
    <<~RUBY
      # frozen_string_literal: true

      class Api::Ping < Boto::Endpoint
        get "/ping"

        def call = { v: app.env.fetch("#{ENV_KEY}", "missing") }
      end
    RUBY
  end

  def ping_value
    JSON.parse(get_ping.body).fetch("v")
  end

  def create_solution(root)
    quiet = { out: StringIO.new, err: StringIO.new }
    Boto::CLI::Commands::New.new([SOLUTION_NAME], cwd: root, **quiet).call
    dir = File.join(root, SOLUTION_NAME)
    Boto::CLI::Commands::Add.new(["webapi", API], cwd: dir, **quiet).call
    dir
  end

  def build_reloader(manifest_watchers: {}, process_env: {})
    @reloader = Boto::CLI::Reloader.new(
      root: @dir, ports: { API => PORT }, env_name: ENV_NAME, out: @out, err: @err,
      load_solution: -> { Boto::Botofile.load(File.join(@dir, BOTOFILE_NAME)) },
      watcher: @watcher, manifest_watchers: manifest_watchers, clock: ZERO_CLOCK,
      process_env: process_env
    )
  end

  def get_ping
    Rack::MockRequest.new(@reloader.app_for(PORT)).get("/ping", AUTH)
  end

  def ping_version
    JSON.parse(get_ping.body).fetch("v")
  end

  def write_ping(source)
    File.write(File.join(@dir, "apps", API, "endpoints", "ping.rb"), source)
  end

  def ping_source(version)
    <<~RUBY
      # frozen_string_literal: true

      class Api::Ping < Boto::Endpoint
        get "/ping"

        def call = { v: #{version} }
      end
    RUBY
  end

  def declare_recorder
    path = File.join(@dir, "apps", API, "config", "app.rb")
    File.write(path, <<~RUBY, mode: "a")
      Boto.configure do |config|
        config.use Boto::CLI::ReloaderTest::Recorder
      end
    RUBY
  end
end
