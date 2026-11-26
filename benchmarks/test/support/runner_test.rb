# frozen_string_literal: true

require "stringio"
require_relative "../test_helper"
require_relative "../../support/runner"

class BenchRunnerTest < Minitest::Test
  FAKE_RESULT = { rps: 1000.0, p99_ms: 12.5 }.freeze
  FAKE_ALLOCATIONS = {
    "boto" => { "hello" => 1.0, "db" => 2.0, "db_schema" => 3.0, "db_auth" => 8.0, "db_auth_redis" => 9.0 },
    "roda" => { "hello" => 4.0, "db" => 5.0 },
    "sinatra" => { "hello" => 6.0, "db" => 7.0 }
  }.freeze
  # boto: hello, db, db_schema, db_auth; roda: hello, db; sinatra: hello, db (db_auth_redis only with Redis)
  COMBINATIONS = 8
  ROUNDS = BenchRunner::ROUNDS
  TOTAL = COMBINATIONS * ROUNDS
  HEADER = "Benchmark: boto, roda, sinatra (fake-tool), #{TOTAL} medições " \
           "(#{COMBINATIONS} combinações x #{ROUNDS} rodadas)\n"
  AUTH = { "Authorization" => "Bearer bench-token" }.freeze

  class FakeLoadTest
    attr_reader :name, :headers_seen

    def initialize(failure: nil)
      @name = "fake-tool"
      @failure = failure
      @headers_seen = []
    end

    def warm_up(_url, headers: {}) = @headers_seen << headers

    def measure(_url, headers: {})
      raise @failure if @failure

      FAKE_RESULT
    end
  end

  FakeServer = Struct.new(:url) do
    def ensure_ok!(_path, headers: {}) = nil
  end

  FAKE_SERVER_FACTORY = ->(_app_path, &block) { block.call(FakeServer.new("http://fake")) }

  def build_runner(out:, quick: false, load_test: FakeLoadTest.new)
    BenchRunner.new(load_test: load_test, allocations: FAKE_ALLOCATIONS, quick: quick,
                    out: out, server_factory: FAKE_SERVER_FACTORY)
  end

  # Runs with db_auth_redis left out, so the combination count is COMBINATIONS.
  def run_without_redis(**options)
    without_redis { build_runner(**options).run }
  end

  def test_prints_header_and_one_progress_line_per_round
    out = StringIO.new
    run_without_redis(out: out)

    lines = out.string.lines
    assert_equal HEADER, lines.first
    assert_equal TOTAL, lines.size - 1
    assert_equal "[1/#{TOTAL}] boto hello round 1/#{ROUNDS} ... 1000 req/s, p99 12.5 ms\n", lines[1]
    assert_equal (1..TOTAL).to_a, lines.drop(1).map { |line| line[/\A\[(\d+)\//, 1].to_i }
    lines.drop(1).each { |line| assert line.end_with?(" 1000 req/s, p99 12.5 ms\n"), line }
  end

  def test_quick_runs_one_round_per_combination
    out = StringIO.new
    run_without_redis(out: out, quick: true)

    lines = out.string.lines
    assert_equal "Benchmark: boto, roda, sinatra (fake-tool), #{COMBINATIONS} medições " \
                 "(#{COMBINATIONS} combinações x 1 rodadas)\n", lines.first
    assert_equal COMBINATIONS, lines.size - 1
    assert_equal "[#{COMBINATIONS}/#{COMBINATIONS}] sinatra db round 1/1 ... 1000 req/s, p99 12.5 ms\n", lines.last
  end

  def test_failed_round_ends_line_with_message_and_reraises
    out = StringIO.new
    load_test = FakeLoadTest.new(failure: RuntimeError.new("boom"))

    assert_raises(RuntimeError) { run_without_redis(out: out, load_test: load_test) }
    assert_equal HEADER, out.string.lines.first
    assert_equal "[1/#{TOTAL}] boto hello round 1/#{ROUNDS} ... falhou: boom\n", out.string.lines.last
  end

  def test_run_returns_summarized_results_by_framework
    result = run_without_redis(out: StringIO.new)

    assert_equal({ "rps" => 1000.0, "p99_ms" => 12.5, "allocations" => 1.0 }, result["boto"]["hello"])
    assert_equal %w[hello db db_schema db_auth], result["boto"].keys
    assert_equal %w[hello db], result["sinatra"].keys
  end

  def test_only_db_auth_rounds_send_authorization_header
    load_test = FakeLoadTest.new
    run_without_redis(out: StringIO.new, load_test: load_test)

    assert_includes load_test.headers_seen, AUTH
    assert_includes load_test.headers_seen, {}
    assert_equal ROUNDS, load_test.headers_seen.count(AUTH)
  end

  def test_db_auth_redis_runs_with_auth_when_redis_is_available
    load_test = FakeLoadTest.new
    result = with_redis { build_runner(out: StringIO.new, load_test: load_test).run }

    assert_equal %w[hello db db_schema db_auth db_auth_redis], result["boto"].keys
    assert_equal 2 * ROUNDS, load_test.headers_seen.count(AUTH)
  end
end
