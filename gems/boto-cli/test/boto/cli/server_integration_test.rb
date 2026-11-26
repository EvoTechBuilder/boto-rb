# frozen_string_literal: true

require "test_helper"
require "net/http"
require "rbconfig"
require "socket"
require "stringio"
require "tmpdir"

# Starts a real `boto run` process and talks to it over the network.
class Boto::CLI::ServerIntegrationTest < Minitest::Test
  GEMS_ROOT = File.expand_path("../../../..", __dir__)
  BOTO_LIB = File.join(GEMS_ROOT, "boto", "lib")
  BOTO_CLI_ROOT = File.join(GEMS_ROOT, "boto-cli")
  BOTO_CLI_LIB = File.join(BOTO_CLI_ROOT, "lib")
  EXECUTABLE = File.join(BOTO_CLI_ROOT, "exe", "boto")
  HOST = "127.0.0.1"
  SERVICE = "itapi"
  STARTUP_TIMEOUT = 10
  POLL_INTERVAL = 0.1

  def test_serves_the_webapi_over_http
    Dir.mktmpdir do |root|
      dir = create_solution(root)
      port = free_port
      pid = spawn_run(dir, port)
      begin
        response = wait_for_health(port)
        assert_equal "200", response.code
        assert_equal %({"status":"ok"}), response.body
      ensure
        stop(pid)
      end
    end
  end

  private

  def create_solution(root)
    quiet = { out: StringIO.new, err: StringIO.new }
    Boto::CLI::Commands::New.new(["shop"], cwd: root, **quiet).call
    dir = File.join(root, "shop")
    Boto::CLI::Commands::Add.new(["webapi", SERVICE], cwd: dir, **quiet).call
    dir
  end

  def free_port
    server = TCPServer.new(HOST, 0)
    server.addr[1]
  ensure
    server&.close
  end

  def spawn_run(dir, port)
    Process.spawn(RbConfig.ruby, "-I", BOTO_LIB, "-I", BOTO_CLI_LIB, EXECUTABLE,
                  "run", "--port", port.to_s, chdir: dir, out: File::NULL, err: File::NULL)
  end

  def wait_for_health(port)
    deadline = monotonic_now + STARTUP_TIMEOUT
    begin
      Net::HTTP.get_response(URI("http://#{HOST}:#{port}/health"))
    rescue Errno::ECONNREFUSED
      flunk "server did not start within #{STARTUP_TIMEOUT}s" if monotonic_now > deadline
      sleep POLL_INTERVAL
      retry
    end
  end

  def monotonic_now
    Process.clock_gettime(Process::CLOCK_MONOTONIC)
  end

  def stop(pid)
    return unless pid

    Process.kill("TERM", pid)
    Process.wait(pid)
  rescue Errno::ESRCH, Errno::ECHILD
    nil
  end
end
