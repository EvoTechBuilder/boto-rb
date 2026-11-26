# frozen_string_literal: true

require "test_helper"
require "securerandom"

class Boto::Redis::RateLimitStoreTest < Minitest::Test
  PERIOD = 60
  # 1_000 falls in window 16 (960..1020), so the window ends 20 seconds later.
  START = 1_000.0
  WINDOW_RESET = 20
  WARMUP_RUNS = 200
  ALLOCATION_WINDOWS = 2

  def setup
    @url = redis_url_or_skip
    @prefix = "boto:test:#{SecureRandom.hex(4)}"
    @now = START
    @clock = -> { @now }
    @redis = ::RedisClient.new(url: @url)
  end

  def teardown
    delete_test_keys if @url
    @redis&.close
  end

  def test_counts_requests_within_one_window
    store = build_store

    assert_equal [1, WINDOW_RESET], store.increment("client", PERIOD)
    assert_equal [2, WINDOW_RESET], store.increment("client", PERIOD)
    assert_equal [3, WINDOW_RESET], store.increment("client", PERIOD)
  end

  def test_new_window_restarts_the_count
    store = build_store
    3.times { store.increment("client", PERIOD) }

    @now = START + PERIOD
    assert_equal [1, WINDOW_RESET], store.increment("client", PERIOD)
  end

  def test_counter_key_is_named_by_window_and_has_a_ttl
    build_store.increment("client", PERIOD)

    key = "#{@prefix}:#{PERIOD}:16:client"
    assert_equal 1, @redis.call("EXISTS", key)
    assert_operator @redis.call("PTTL", key), :>, 0
    assert_operator @redis.call("PTTL", key), :<=, WINDOW_RESET * 1_000
  end

  # 1_000.5 is half way through window 1000 of a one second period, so the TTL must be at most 500 ms.
  def test_counter_ttl_does_not_outlive_its_window
    @now = 1_000.5
    assert_equal [1, 1], build_store.increment("client", 1)

    assert_operator @redis.call("PTTL", "#{@prefix}:1:1000:client"), :<=, 500
  end

  def test_stores_pointing_at_the_same_redis_add_up
    first = build_store
    second = build_store

    assert_equal [1, WINDOW_RESET], first.increment("client", PERIOD)
    assert_equal [2, WINDOW_RESET], second.increment("client", PERIOD)
    assert_equal [3, WINDOW_RESET], first.increment("client", PERIOD)
  end

  def test_keeps_counting_after_script_flush
    store = build_store
    store.increment("client", PERIOD)
    @redis.call("SCRIPT", "FLUSH")

    assert_equal [2, WINDOW_RESET], store.increment("client", PERIOD)
  end

  def test_prefix_isolates_counters
    other = "#{@prefix}:other"
    first = build_store
    second = build_store(prefix: other)

    assert_equal [1, WINDOW_RESET], first.increment("client", PERIOD)
    assert_equal [1, WINDOW_RESET], second.increment("client", PERIOD)
  ensure
    delete_keys_matching("#{other}:*")
  end

  def test_concurrent_threads_share_the_pool_without_losing_counts
    store = build_store
    threads = Array.new(4) { Thread.new { Array.new(50) { store.increment("client", PERIOD).first } } }
    counts = threads.flat_map(&:value).sort

    assert_equal (1..200).to_a, counts
  end

  def test_counter_key_changes_when_the_window_changes
    store = build_store
    assert_equal [1, WINDOW_RESET], store.increment("client", PERIOD)

    @now = START + PERIOD
    assert_equal [1, WINDOW_RESET], store.increment("client", PERIOD)

    assert_equal 1, @redis.call("EXISTS", "#{@prefix}:#{PERIOD}:16:client")
    assert_equal 1, @redis.call("EXISTS", "#{@prefix}:#{PERIOD}:17:client")
  end

  def test_counter_key_allocates_only_the_final_string
    store = build_store
    WARMUP_RUNS.times { store.send(:counter_key, "client", PERIOD, 16) }

    count = measure_allocations { store.send(:counter_key, "client", PERIOD, 16) }

    assert_operator count, :<=, 1
  end

  private

  def measure_allocations(&block)
    Array.new(ALLOCATION_WINDOWS) { allocations(&block) }.last
  end

  def allocations
    before = GC.stat(:total_allocated_objects)
    yield
    GC.stat(:total_allocated_objects) - before
  end

  def build_store(**options)
    Boto::Redis::RateLimitStore.new(url: @url, prefix: @prefix, clock: @clock, **options)
  end

  def delete_test_keys
    delete_keys_matching("#{@prefix}:*")
  end

  def delete_keys_matching(pattern)
    @redis.scan("MATCH", pattern).each_slice(100) { |keys| @redis.call("DEL", *keys) }
  end
end
