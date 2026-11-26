# frozen_string_literal: true

require_relative "../test_helper"
require "tmpdir"
require_relative "../../support/server"

class BenchServerTest < Minitest::Test
  APP_PATH = "/project/apps/boto/hello.ru"
  TERM_IGNORING_SCRIPT = "trap('TERM') {}; $stdout.puts 'ready'; $stdout.flush; sleep 60"

  def test_log_path_is_named_after_framework_and_scenario
    server = BenchServer.new(APP_PATH, port: 1, logs_dir: "/logs")
    assert_equal "/logs/boto-hello.log", server.log_path
  end

  def test_log_tail_returns_last_lines
    Dir.mktmpdir do |dir|
      server = BenchServer.new(APP_PATH, port: 1, logs_dir: dir)
      File.write(server.log_path, (1..30).map { |n| "line #{n}\n" }.join)
      assert_equal((11..30).map { |n| "line #{n}\n" }.join, server.log_tail)
      assert_equal "line 30\n", server.log_tail(1)
    end
  end

  def test_log_tail_is_empty_without_log_file
    Dir.mktmpdir do |dir|
      assert_equal "", BenchServer.new(APP_PATH, port: 1, logs_dir: dir).log_tail
    end
  end

  def test_stop_kills_process_that_ignores_term
    Dir.mktmpdir do |dir|
      server = BenchServer.new(APP_PATH, port: 1, stop_timeout: 1, logs_dir: dir)
      pid, ready_reader = spawn_term_ignoring_process
      server.attach_pid(pid)
      assert_equal "ready\n", ready_reader.gets
      started = monotonic
      server.stop
      assert_operator monotonic - started, :<, 3
      assert_raises(Errno::ESRCH) { Process.kill(0, pid) }
    end
  end

  def test_stop_without_started_server_does_nothing
    BenchServer.new(APP_PATH, port: 1).stop
  end

  private

  def spawn_term_ignoring_process
    reader, writer = IO.pipe
    pid = Process.spawn("ruby", "-e", TERM_IGNORING_SCRIPT, pgroup: true, out: writer, err: File::NULL)
    writer.close
    [pid, reader]
  end

  def monotonic = Process.clock_gettime(Process::CLOCK_MONOTONIC)
end
