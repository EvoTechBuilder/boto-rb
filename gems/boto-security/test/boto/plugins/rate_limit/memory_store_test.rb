# frozen_string_literal: true

require "test_helper"

class Boto::Plugins::RateLimit::MemoryStoreTest < Minitest::Test
  PERIOD = 10

  def setup
    @now = 1.0
    @store = Boto::Plugins::RateLimit::MemoryStore.new(clock: -> { @now })
  end

  def test_counts_requests_within_the_window
    assert_equal [1, 9], @store.increment("a", PERIOD)
    assert_equal [2, 9], @store.increment("a", PERIOD)
    assert_equal [1, 9], @store.increment("b", PERIOD)
  end

  def test_resets_the_count_when_the_window_changes
    @store.increment("a", PERIOD)
    @now = 9.5
    assert_equal [2, 1], @store.increment("a", PERIOD)

    @now = 10.0
    assert_equal [1, 10], @store.increment("a", PERIOD)
  end

  def test_reset_in_rounds_up_to_whole_seconds_and_is_at_least_one
    @now = 3.2
    assert_equal [1, 7], @store.increment("a", PERIOD)

    @now = 9.999
    assert_equal [2, 1], @store.increment("a", PERIOD)
  end

  def test_drops_counters_of_past_windows
    @store.increment("a", PERIOD)
    @store.increment("b", PERIOD)
    assert_equal 2, @store.size

    @now = 10.0
    @store.increment("c", PERIOD)
    assert_equal 1, @store.size
  end

  def test_counts_concurrent_increments_without_losing_any
    threads = Array.new(4) { Thread.new { 25.times { @store.increment("k", PERIOD) } } }
    threads.each(&:join)

    assert_equal [101, 9], @store.increment("k", PERIOD)
  end

  def test_drops_the_oldest_key_when_the_window_is_full
    store = build_store(max_keys: 3)
    %w[a b c d].each { |key| store.increment(key, PERIOD) }

    assert_equal 3, store.size
    assert_equal [1, 9], store.increment("a", PERIOD)
  end

  def test_incrementing_an_existing_key_evicts_nobody
    store = build_store(max_keys: 3)
    %w[a b c].each { |key| store.increment(key, PERIOD) }

    assert_equal [2, 9], store.increment("a", PERIOD)
    assert_equal 3, store.size

    store.increment("d", PERIOD)
    assert_equal [2, 9], store.increment("b", PERIOD)
    assert_equal [1, 9], store.increment("a", PERIOD)
  end

  def test_evicts_in_insertion_order
    store = build_store(max_keys: 3)
    %w[a b c d e].each { |key| store.increment(key, PERIOD) }

    assert_equal [2, 9], store.increment("c", PERIOD)
    assert_equal [2, 9], store.increment("d", PERIOD)
  end

  def test_rejects_invalid_max_keys
    [0, -1, "x", nil].each do |value|
      assert_raises(ArgumentError) { build_store(max_keys: value) }
    end
  end

  def test_max_keys_applies_per_window
    store = build_store(max_keys: 3)
    %w[a b c].each { |key| store.increment(key, PERIOD) }

    @now = 10.0
    assert_equal [1, 10], store.increment("a", PERIOD)
    assert_equal 1, store.size
  end

  def test_size_never_exceeds_max_keys_under_a_flood_of_keys
    store = build_store(max_keys: 1_000)
    largest_size = 0

    10_000.times do |index|
      store.increment("ip-#{index}", PERIOD)
      largest_size = [largest_size, store.size].max
    end

    assert_equal 1_000, largest_size
  end

  private

  def build_store(max_keys:)
    Boto::Plugins::RateLimit::MemoryStore.new(clock: -> { @now }, max_keys: max_keys)
  end
end
