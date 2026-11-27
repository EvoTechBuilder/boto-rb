# frozen_string_literal: true

require "test_helper"
require "async"
require "fileutils"
require "json"
require "rack/mock"
require "stringio"
require "tmpdir"

# Named outside Commands: any constant there is listed as a command by the runner.
class Boto::CLI::RunCommandTest < Minitest::Test
  SOLUTION_NAME = "shop"
  LIBRARY = "rundomain"
  WEBAPI = "runapi"
  BILLING = "runbilling"
  HOST = "127.0.0.1"
  LIFECYCLE = "runlifecycle"
  RELOAD_API = "reloadapi"
  DEV_TOKEN = "dev-token"

  # Records the lifecycle calls of the plugin declared by the solution's config/app.rb.
  class LifecycleRecorder < Boto::Plugin
    EVENTS = []

    def start = EVENTS << :start
    def stop = EVENTS << :stop
  end

  class FakeServer
    attr_reader :apps_by_port, :host

    def initialize(apps_by_port, host:)
      @apps_by_port = apps_by_port
      @host = host
    end

    def run; end
  end

  class InterruptedServer < FakeServer
    def run = raise(Interrupt)
  end

  # Like Server#run, runs the block inside a reactor; the signals of the subclass arrive before the block.
  class SignalingServer < FakeServer
    SIGNAL_SETTLE = 0.01
    attr_reader :drain_calls

    def self.signals = []

    def initialize(apps_by_port, host:)
      super
      @drain_calls = []
    end

    def run
      Async do
        self.class.signals.each do |name|
          Process.kill(name, Process.pid)
          sleep SIGNAL_SETTLE
        end
        yield self
      end
    end

    def drain(delay:, timeout:, interrupted:)
      @drain_calls << { delay: delay, timeout: timeout, interrupted: interrupted.call }
      true
    end
  end

  # Runs the given script with the apps instead of waiting for requests from outside.
  class ScriptedServer < FakeServer
    def initialize(apps_by_port, host:, script:)
      super(apps_by_port, host: host)
      @script = script
    end

    def run = @script.call(apps_by_port)
  end

  class TermServer < SignalingServer
    def self.signals = %w[TERM]
  end

  class TermThenIntServer < SignalingServer
    def self.signals = %w[TERM INT]
  end

  # Booting loads the projects with Zeitwerk, so the shared solution is built once for this class.
  def self.solution_dir
    @solution_dir ||= create_solution(Dir.mktmpdir, [["library", LIBRARY], ["webapi", WEBAPI], ["webapi", BILLING]])
                      .tap { |dir| Minitest.after_run { FileUtils.remove_entry(File.dirname(dir)) } }
  end

  def self.create_solution(root, projects)
    quiet = { out: StringIO.new, err: StringIO.new }
    Boto::CLI::Commands::New.new([SOLUTION_NAME], cwd: root, **quiet).call
    dir = File.join(root, SOLUTION_NAME)
    projects.each { |template, name| Boto::CLI::Commands::Add.new([template, name], cwd: dir, **quiet).call }
    dir
  end

  def test_code_glob_watches_repositories_with_the_other_code_folders
    Dir.mktmpdir do |dir|
      %w[repositories/thing_repository.rb endpoints/show.rb config/app.rb test/show_test.rb].each do |path|
        FileUtils.mkdir_p(File.join(dir, File.dirname(path)))
        File.write(File.join(dir, path), "")
      end

      matches = Dir.glob(Boto::CLI::Commands::Run::CODE_GLOB, base: dir).sort

      assert_equal %w[config/app.rb endpoints/show.rb repositories/thing_repository.rb], matches
    end
  end

  def test_serves_servable_projects_in_order_on_consecutive_ports
    out = StringIO.new
    assert_equal 0, run_command([], out: out)

    assert_equal [3000, 3001], @server.apps_by_port.keys
    assert_equal HOST, @server.host
    assert_includes out.string, "Boto running (Ctrl-C to stop, reload on)"
    assert_includes out.string, "  #{WEBAPI}  http://127.0.0.1:3000\n"
    assert_includes out.string, "  #{BILLING}  http://127.0.0.1:3001\n"
    refute_includes out.string, LIBRARY
  end

  def test_each_port_answers_the_health_check
    run_command([])

    response = Rack::MockRequest.new(@server.apps_by_port.fetch(3000)).get("/health/live")
    assert_equal 200, response.status
    assert_equal %({"status":"ok"}), response.body
  end

  def test_port_and_host_options_are_passed_to_the_server
    assert_equal 0, run_command(%w[--port 4000 --host 0.0.0.0])

    assert_equal [4000, 4001], @server.apps_by_port.keys
    assert_equal "0.0.0.0", @server.host
  end

  def test_runs_only_the_named_project
    assert_equal 0, run_command([BILLING])

    assert_equal [3000], @server.apps_by_port.keys
  end

  def test_library_project_cannot_be_served
    error = assert_raises(Boto::CLI::Error) { run_command([LIBRARY]) }
    assert_equal %(project "#{LIBRARY}" (library) cannot be served), error.message
  end

  def test_unknown_project_raises
    error = assert_raises(Boto::CLI::Error) { run_command(["ghost"]) }
    assert_equal %(unknown project "ghost"), error.message
  end

  def test_invalid_option_raises
    error = assert_raises(Boto::CLI::Error) { run_command(["--bogus"]) }
    assert_includes error.message, "--bogus"
  end

  def test_more_than_one_project_raises_usage
    error = assert_raises(Boto::CLI::Error) { run_command([WEBAPI, BILLING]) }
    assert_equal "Usage: boto run [project] [--port N] [--host H]", error.message
  end

  def test_invalid_port_raises
    error = assert_raises(Boto::CLI::Error) { run_command(%w[--port 0]) }
    assert_equal %(invalid port "0"), error.message
  end

  def test_solution_without_servable_projects_raises
    Dir.mktmpdir do |root|
      dir = self.class.create_solution(root, [["library", LIBRARY]])

      error = assert_raises(Boto::CLI::Error) { run_command([], cwd: dir) }
      assert_equal "no servable projects (webapi, microservice)", error.message
    end
  end

  def test_interrupt_stops_the_server_and_succeeds
    out = StringIO.new

    assert_equal 0, run_command([], out: out, server_class: InterruptedServer)
    assert_includes out.string, "Stopping"
  end

  def test_stopping_the_run_stops_the_plugins_of_its_apps
    LifecycleRecorder::EVENTS.clear
    Dir.mktmpdir do |root|
      dir = self.class.create_solution(root, [["webapi", LIFECYCLE]])
      declare_lifecycle_recorder(dir)

      assert_equal 0, run_command([], cwd: dir, server_class: InterruptedServer)
    end

    assert_equal %i[start stop], LifecycleRecorder::EVENTS
  end

  def test_first_signal_drains_with_the_timing_options
    out = StringIO.new

    assert_equal 0, run_command(%w[--shutdown-timeout 3 --drain-delay 0.5], out: out, server_class: TermServer)

    assert_includes out.string, "Stopping (draining up to 3 s)"
    assert_equal [{ delay: 0.5, timeout: 3.0, interrupted: false }], @server.drain_calls
  end

  def test_drain_defaults_to_no_delay_and_25_seconds
    run_command([], server_class: TermServer)

    assert_equal [{ delay: 0, timeout: 25, interrupted: false }], @server.drain_calls
  end

  def test_first_signal_stops_the_plugins_after_draining
    LifecycleRecorder::EVENTS.clear
    Dir.mktmpdir do |root|
      dir = self.class.create_solution(root, [["webapi", LIFECYCLE]])
      declare_lifecycle_recorder(dir)

      assert_equal 0, run_command([], cwd: dir, server_class: TermServer)
    end

    assert_equal %i[start stop], LifecycleRecorder::EVENTS
  end

  def test_development_serves_reloading_apps
    out = StringIO.new

    assert_equal 0, run_command([], out: out)

    assert @server.apps_by_port.values.all? { |app| app.is_a?(Boto::CLI::ReloadingApp) }
    assert_includes out.string, "reload on"
  end

  def test_no_reload_option_serves_the_booted_apps
    out = StringIO.new

    assert_equal 0, run_command(%w[--no-reload], out: out)

    assert @server.apps_by_port.values.all? { |app| app.is_a?(Boto::App) }
    assert_includes out.string, "Boto running (Ctrl-C to stop)\n"
    refute_includes out.string, "reload on"
  end

  def test_production_serves_the_booted_apps_without_reload
    out = StringIO.new

    assert_equal 0, run_command([], out: out, env: { "BOTO_ENV" => "production", "API_TOKENS" => "t" })

    assert @server.apps_by_port.values.all? { |app| app.is_a?(Boto::App) }
    refute_includes out.string, "reload on"
  end

  def test_help_lists_no_reload
    out = StringIO.new
    runner = Boto::CLI::Runner.new(out: out, err: StringIO.new, cwd: self.class.solution_dir)

    assert_equal 0, runner.run(%w[help run])
    assert_includes out.string, "--no-reload"
  end

  def test_development_reload_serves_the_changed_endpoint
    responses = []
    Dir.mktmpdir do |root|
      dir = self.class.create_solution(root, [["webapi", RELOAD_API]])
      path = write_ping(dir, ping_source(1))
      script = lambda do |apps_by_port|
        responses << ping_version(apps_by_port.fetch(3000))
        write_ping(dir, ping_source(2))
        touch_future(path)
        responses << ping_version(apps_by_port.fetch(3000))
      end
      factory = ->(apps_by_port, host:) { ScriptedServer.new(apps_by_port, host: host, script: script) }

      Boto::CLI::Commands::Run.new([], out: StringIO.new, err: StringIO.new, cwd: dir,
                                       server_factory: factory, env: {}).call
    end

    assert_equal [1, 2], responses
  end

  def test_second_signal_during_the_drain_fails_and_marks_the_drain_interrupted
    out = StringIO.new

    assert_equal 1, run_command([], out: out, server_class: TermThenIntServer)

    assert_equal true, @server.drain_calls.last[:interrupted]
  end

  def test_invalid_shutdown_timeout_raises
    error = assert_raises(Boto::CLI::Error) { run_command(%w[--shutdown-timeout 0]) }
    assert_equal %(invalid shutdown timeout "0.0"), error.message
  end

  def test_negative_drain_delay_raises
    error = assert_raises(Boto::CLI::Error) { run_command(%w[--drain-delay=-1]) }
    assert_equal %(invalid drain delay "-1.0"), error.message
  end

  def test_non_numeric_drain_delay_raises
    error = assert_raises(Boto::CLI::Error) { run_command(%w[--drain-delay soon]) }
    assert_includes error.message, "soon"
  end

  private

  # Appends to the template's config/app.rb, which already declares the security plugins.
  def declare_lifecycle_recorder(dir)
    path = File.join(dir, "apps", LIFECYCLE, "config", "app.rb")
    File.write(path, <<~RUBY, mode: "a")
      Boto.configure do |config|
        config.use Boto::CLI::RunCommandTest::LifecycleRecorder
      end
    RUBY
  end

  def run_command(argv, cwd: self.class.solution_dir, out: StringIO.new, server_class: FakeServer, env: {})
    factory = ->(apps_by_port, host:) { @server = server_class.new(apps_by_port, host: host) }
    Boto::CLI::Commands::Run.new(argv, out: out, err: StringIO.new, cwd: cwd,
                                       server_factory: factory, env: env).call
  end

  def write_ping(dir, source)
    path = File.join(dir, "apps", RELOAD_API, "endpoints", "ping.rb")
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, source)
    path
  end

  # A future mtime makes the change visible without depending on the clock's resolution.
  def touch_future(path)
    time = Time.now + 5
    File.utime(time, time, path)
  end

  def ping_source(version)
    <<~RUBY
      class #{Boto::Project.namespace_for(RELOAD_API)}::Ping < Boto::Endpoint
        get "/ping"

        def call = { v: #{version} }
      end
    RUBY
  end

  def ping_version(app)
    response = Rack::MockRequest.new(app).get("/ping", "HTTP_AUTHORIZATION" => "Bearer #{DEV_TOKEN}")
    JSON.parse(response.body).fetch("v")
  end
end
