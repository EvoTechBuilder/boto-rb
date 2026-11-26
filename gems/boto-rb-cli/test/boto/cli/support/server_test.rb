# frozen_string_literal: true

require "test_helper"
require "async"
require "async/http/internet"
require "socket"

class Boto::CLI::ServerTest < Minitest::Test
  HOST = "127.0.0.1"
  OK = [200, { "content-type" => "text/plain" }, ["done"]].freeze
  SLOW_SECONDS = 0.3
  SETTLE = 0.05

  # Records whether the app was told to drain, as Boto::App does.
  class DrainAwareApp
    attr_reader :draining

    def call(_env) = OK

    def drain!
      @draining = true
    end
  end

  def test_drain_finishes_requests_in_flight_and_refuses_new_connections
    port = free_port
    outcome = {}
    server = server_for(port, ->(_env) { sleep SLOW_SECONDS; OK })

    _, err = capture_io do
      server.run do
        task = Async::Task.current
        request = task.async { outcome[:status] = get(port) }
        sleep SETTLE
        drain = task.async { outcome[:drained] = server.drain(delay: 0, timeout: 5) }
        sleep SETTLE
        outcome[:refused] = refused?(port)
        [drain, request].each(&:wait)
      end
    end

    assert_equal 200, outcome[:status]
    assert outcome[:drained]
    assert outcome[:refused]
    refute_match(/IOError|unhandled/, err)
  end

  def test_drain_cuts_requests_that_outlast_the_timeout
    port = free_port
    outcome = {}
    server = server_for(port, ->(_env) { sleep SLOW_SECONDS; OK })
    started = monotonic_now

    server.run do
      request = Async::Task.current.async { outcome[:status] = safe_get(port) }
      sleep SETTLE
      outcome[:drained] = server.drain(delay: 0, timeout: 0.1)
      request.wait
    end

    refute outcome[:drained]
    assert_nil outcome[:status]
    assert_operator monotonic_now - started, :<, SLOW_SECONDS
  end

  def test_drain_keeps_accepting_during_the_delay
    port = free_port
    outcome = {}
    server = server_for(port, ->(_env) { OK })

    server.run do
      drain = Async::Task.current.async { server.drain(delay: 0.2, timeout: 0.1) }
      sleep SETTLE
      outcome[:during_delay] = reachable?(port)
      sleep 0.3
      outcome[:after_delay] = reachable?(port)
      drain.wait
    end

    assert outcome[:during_delay]
    refute outcome[:after_delay]
  end

  def test_drain_tells_apps_that_are_draining
    port = free_port
    app = DrainAwareApp.new
    server = server_for(port, app)

    server.run { server.drain(delay: 0, timeout: 0.1) }

    assert app.draining
  end

  private

  def server_for(port, app)
    Boto::CLI::Server.new({ port => app }, host: HOST)
  end

  def free_port
    server = TCPServer.new(HOST, 0)
    server.addr[1]
  ensure
    server&.close
  end

  def get(port)
    internet = Async::HTTP::Internet.new
    response = internet.get("http://#{HOST}:#{port}/")
    response.read
    response.status
  ensure
    internet&.close
  end

  # A cut request ends the client side with an error instead of a response.
  def safe_get(port)
    get(port)
  rescue StandardError
    nil
  end

  def refused?(port)
    !reachable?(port)
  end

  def reachable?(port)
    TCPSocket.new(HOST, port).close
    true
  rescue Errno::ECONNREFUSED
    false
  end

  def monotonic_now
    Process.clock_gettime(Process::CLOCK_MONOTONIC)
  end
end
