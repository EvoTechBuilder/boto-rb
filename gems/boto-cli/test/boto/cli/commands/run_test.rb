# frozen_string_literal: true

require "test_helper"
require "fileutils"
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

  def test_serves_servable_projects_in_order_on_consecutive_ports
    out = StringIO.new
    assert_equal 0, run_command([], out: out)

    assert_equal [3000, 3001], @server.apps_by_port.keys
    assert_equal HOST, @server.host
    assert_includes out.string, "Boto running (Ctrl-C to stop)"
    assert_includes out.string, "  #{WEBAPI}  http://127.0.0.1:3000\n"
    assert_includes out.string, "  #{BILLING}  http://127.0.0.1:3001\n"
    refute_includes out.string, LIBRARY
  end

  def test_each_port_answers_the_health_check
    run_command([])

    response = Rack::MockRequest.new(@server.apps_by_port.fetch(3000)).get("/health")
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
    assert_equal "usage: boto run [project] [--port N] [--host H]", error.message
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

  private

  def run_command(argv, cwd: self.class.solution_dir, out: StringIO.new, server_class: FakeServer)
    factory = ->(apps_by_port, host:) { @server = server_class.new(apps_by_port, host: host) }
    Boto::CLI::Commands::Run.new(argv, out: out, err: StringIO.new, cwd: cwd,
                                       server_factory: factory, env: {}).call
  end
end
