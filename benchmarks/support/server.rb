# frozen_string_literal: true

require "fileutils"
require "net/http"
require "socket"
require "uri"
require_relative "scenarios"

# Starts one falcon process per app and kills its whole process group on stop.
# Falcon's output goes to results/logs/<framework>-<scenario>.log.
class BenchServer
  class Error < StandardError; end

  HOST = "127.0.0.1"
  OK_STATUS = "200"
  READY_TIMEOUT = 15
  READY_POLL_INTERVAL = 0.1
  STOP_TIMEOUT = 10
  STOP_POLL_INTERVAL = 0.1
  HTTP_TIMEOUT = 5
  LOG_TAIL_LINES = 20
  LOGS_DIR = File.join(BenchScenarios::ROOT, "results", "logs")
  FALCON_COMMAND = %w[bundle exec falcon serve].freeze
  # Port still closed or reset while falcon boots; any other error is a real failure.
  NOT_LISTENING_ERRORS = [Errno::ECONNREFUSED, Errno::EADDRNOTAVAIL, Errno::ECONNRESET].freeze

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

  def initialize(app_path, port: self.class.free_port, stop_timeout: STOP_TIMEOUT, logs_dir: LOGS_DIR)
    @app_path = app_path
    @port = port
    @stop_timeout = stop_timeout
    @logs_dir = logs_dir
    @pid = nil
  end

  def url = "http://#{HOST}:#{port}"

  def log_path = File.join(@logs_dir, "#{app_name}.log")

  def start
    FileUtils.mkdir_p(@logs_dir)
    @pid = Process.spawn(*command, chdir: BenchScenarios::ROOT, pgroup: true,
                                   out: [log_path, "w"], err: [:child, :out])
    wait_until_listening
  end

  # Uso de teste: adota um processo já criado, sem passar por start.
  def attach_pid(pid)
    @pid = pid
  end

  def stop
    return unless @pid

    Process.kill("TERM", -@pid)
    kill_if_still_running
  rescue Errno::ESRCH, Errno::ECHILD
    nil
  ensure
    @pid = nil
  end

  def ensure_ok!(path, headers: {})
    code = Net::HTTP.start(HOST, port, open_timeout: HTTP_TIMEOUT, read_timeout: HTTP_TIMEOUT) do |http|
      http.get(path, headers)
    end.code
    raise failure("#{url}#{path} respondeu #{code}, esperado #{OK_STATUS}") unless code == OK_STATUS
  rescue Net::OpenTimeout, Net::ReadTimeout, SystemCallError => e
    raise failure("#{url}#{path} falhou: #{e.class}")
  end

  def log_tail(lines = LOG_TAIL_LINES)
    return "" unless File.exist?(log_path)

    File.readlines(log_path).last(lines).join
  end

  private

  def app_name = "#{File.basename(File.dirname(@app_path))}-#{File.basename(@app_path, '.ru')}"

  def command
    [*FALCON_COMMAND, "--bind", url, "--count", "1", "--config", @app_path]
  end

  def wait_until_listening
    deadline = monotonic + READY_TIMEOUT
    until listening?
      raise failure("falcon não respondeu em #{url} em #{READY_TIMEOUT}s") if monotonic > deadline

      sleep READY_POLL_INTERVAL
    end
  end

  def listening?
    TCPSocket.new(HOST, port).close
    true
  rescue *NOT_LISTENING_ERRORS
    false
  end

  def kill_if_still_running
    return if wait_for_exit

    Process.kill("KILL", -@pid)
    Process.wait(@pid)
  end

  # Process.wait with WNOHANG returns nil while the child is alive, and reaps it once it exits.
  def wait_for_exit
    deadline = monotonic + @stop_timeout
    until Process.wait(@pid, Process::WNOHANG)
      return false if monotonic > deadline

      sleep STOP_POLL_INTERVAL
    end
    true
  end

  def failure(message)
    Error.new([message, log_tail].reject(&:empty?).join("\n"))
  end

  def monotonic = Process.clock_gettime(Process::CLOCK_MONOTONIC)
end
