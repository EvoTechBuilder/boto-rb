# frozen_string_literal: true

require_relative "../test_helper"
require "tmpdir"
require_relative "../../support/load_test"

class BenchLoadTestTest < Minitest::Test
  AB_OUTPUT = <<~OUT
    Requests per second:    12345.67 [#/sec] (mean)
    Percentage of the requests served within a certain time (ms)
      50%      3
      99%     12
     100%     40 (longest request)
  OUT

  WRK_OUTPUT = <<~OUT
    Requests/sec:  9876.54
    Latency Distribution
       50%  800.00us
       99%    1.50ms
  OUT

  def test_ab_parses_rps_and_p99
    result = BenchLoadTest::Ab.new(quick: true).parse(AB_OUTPUT)
    assert_in_delta 12_345.67, result[:rps]
    assert_in_delta 12.0, result[:p99_ms]
  end

  def test_wrk_converts_p99_to_ms
    result = BenchLoadTest::Wrk.new(quick: true).parse(WRK_OUTPUT)
    assert_in_delta 9876.54, result[:rps]
    assert_in_delta 1.5, result[:p99_ms]
  end

  def test_wrk_converts_microseconds_and_seconds
    assert_in_delta 2.0, BenchLoadTest::Wrk.new(quick: true).parse("Requests/sec: 1\n   99%  2000.00us\n")[:p99_ms]
    assert_in_delta 3000.0, BenchLoadTest::Wrk.new(quick: true).parse("Requests/sec: 1\n   99%  3.00s\n")[:p99_ms]
  end

  def test_missing_metric_raises
    error = assert_raises(BenchLoadTest::Error) { BenchLoadTest::Ab.new(quick: true).parse("nothing") }
    assert_match(/não encontrada/, error.message)
  end

  def test_build_prefers_wrk_when_on_path
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, "wrk"), "")
      File.chmod(0o755, File.join(dir, "wrk"))
      assert_instance_of BenchLoadTest::Wrk, BenchLoadTest.build(quick: true, path: dir)
    end
  end

  def test_build_falls_back_to_ab
    Dir.mktmpdir do |dir|
      assert_instance_of BenchLoadTest::Ab, BenchLoadTest.build(quick: true, path: dir)
    end
  end

  def test_quick_profile_uses_fewer_requests
    ab = BenchLoadTest::Ab.new(quick: true)
    assert_includes ab.command("http://x/", 2_000), "2000"
  end
end
