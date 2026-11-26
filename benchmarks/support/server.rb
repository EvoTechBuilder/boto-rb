# frozen_string_literal: true

require "net/http"
require "socket"
require "uri"
require_relative "scenarios"

# Starts one falcon process per app and kills its whole process group on stop.
class BenchServer
  class Error < StandardError; end

  HOST = "127.0.0.1"
  OK_STATUS = "200"
  READY_TIMEOUT = 15
  READY_POLL_INTERVAL = 0.1
  FALCON_COMMAND = %w[bundle exec falcon serve].freeze

  def self.free_port
    TCPServer.open(HOST, 0) { |socket| socket.addr[1] }
  end

  def self.open(app_path)
    server = new(app_path)
    server.start
    yield server
  ensure
    server&.stop
  end

  attr_reader :port

  def initialize(app_path, port: self.class.free_port)
    @app_path = app_path
    @port = port
    @pid = nil
  end

  def url = "http://#{HOST}:#{port}"

  def start
    @pid = Process.spawn(*command, chdir: BenchScenarios::ROOT, pgroup: true, out: File::NULL, err: File::NULL)
    wait_until_listening
  end

  def stop
    return unless @pid

    Process.kill("TERM", -@pid)
    Process.wait(@pid)
  rescue Errno::ESRCH, Errno::ECHILD
    nil
  ensure
    @pid = nil
  end

  def ensure_ok!(path)
    code = Net::HTTP.get_response(URI("#{url}#{path}")).code
    raise Error, "#{url}#{path} respondeu #{code}, esperado #{OK_STATUS}" unless code == OK_STATUS
  end

  private

  def command
    [*FALCON_COMMAND, "--bind", url, "--count", "1", "--config", @app_path]
  end

  def wait_until_listening
    deadline = monotonic + READY_TIMEOUT
    until listening?
      raise Error, "falcon não respondeu em #{url} em #{READY_TIMEOUT}s" if monotonic > deadline

      sleep READY_POLL_INTERVAL
    end
  end

  def listening?
    TCPSocket.new(HOST, port).close
    true
  rescue Errno::ECONNREFUSED
    false
  end

  def monotonic = Process.clock_gettime(Process::CLOCK_MONOTONIC)
end
