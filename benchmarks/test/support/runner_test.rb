# frozen_string_literal: true

require "stringio"
require_relative "../test_helper"
require_relative "../../support/runner"

class BenchRunnerTest < Minitest::Test
  FAKE_RESULT = { rps: 1000.0, p99_ms: 12.5 }.freeze
  FAKE_ALLOCATIONS = {
    "boto" => { "hello" => 1.0, "db" => 2.0, "db_schema" => 3.0 },
    "roda" => { "hello" => 4.0, "db" => 5.0 },
    "sinatra" => { "hello" => 6.0, "db" => 7.0 }
  }.freeze
  # boto: hello, db, db_schema; roda: hello, db; sinatra: hello, db
  COMBINATIONS = 7
  ROUNDS = BenchRunner::ROUNDS
  TOTAL = COMBINATIONS * ROUNDS
  HEADER = "Benchmark: boto, roda, sinatra (fake-tool), #{TOTAL} medições " \
           "(#{COMBINATIONS} combinações x #{ROUNDS} rodadas)\n"

  class FakeLoadTest
    attr_reader :name

    def initialize(failure: nil)
      @name = "fake-tool"
      @failure = failure
    end

    def warm_up(_url) = nil

    def measure(_url)
      raise @failure if @failure

      FAKE_RESULT
    end
  end

  FakeServer = Struct.new(:url) do
    def ensure_ok!(_path) = nil
  end

  FAKE_SERVER_FACTORY = ->(_app_path, &block) { block.call(FakeServer.new("http://fake")) }

  def build_runner(out:, quick: false, load_test: FakeLoadTest.new)
    BenchRunner.new(load_test: load_test, allocations: FAKE_ALLOCATIONS, quick: quick,
                    out: out, server_factory: FAKE_SERVER_FACTORY)
  end

  def test_prints_header_and_one_progress_line_per_round
    out = StringIO.new
    build_runner(out: out).run

    lines = out.string.lines
    assert_equal HEADER, lines.first
    assert_equal TOTAL, lines.size - 1
    assert_equal "[1/#{TOTAL}] boto hello round 1/#{ROUNDS} ... 1000 req/s, p99 12.5 ms\n", lines[1]
    assert_equal (1..TOTAL).to_a, lines.drop(1).map { |line| line[/\A\[(\d+)\//, 1].to_i }
    lines.drop(1).each { |line| assert line.end_with?(" 1000 req/s, p99 12.5 ms\n"), line }
  end

  def test_quick_runs_one_round_per_combination
    out = StringIO.new
    build_runner(out: out, quick: true).run

    lines = out.string.lines
    assert_equal "Benchmark: boto, roda, sinatra (fake-tool), #{COMBINATIONS} medições " \
                 "(#{COMBINATIONS} combinações x 1 rodadas)\n", lines.first
    assert_equal COMBINATIONS, lines.size - 1
    assert_equal "[#{COMBINATIONS}/#{COMBINATIONS}] sinatra db round 1/1 ... 1000 req/s, p99 12.5 ms\n", lines.last
  end

  def test_failed_round_ends_line_with_message_and_reraises
    out = StringIO.new
    runner = build_runner(out: out, load_test: FakeLoadTest.new(failure: RuntimeError.new("boom")))

    assert_raises(RuntimeError) { runner.run }
    assert_equal HEADER, out.string.lines.first
    assert_equal "[1/#{TOTAL}] boto hello round 1/#{ROUNDS} ... falhou: boom\n", out.string.lines.last
  end

  def test_run_returns_summarized_results_by_framework
    result = build_runner(out: StringIO.new).run

    assert_equal({ "rps" => 1000.0, "p99_ms" => 12.5, "allocations" => 1.0 }, result["boto"]["hello"])
    assert_equal %w[hello db db_schema], result["boto"].keys
    assert_equal %w[hello db], result["sinatra"].keys
  end
end
