# frozen_string_literal: true

require "test_helper"
require "socket"
require "stringio"

class Boto::Redis::RateLimitStore::FailureTest < Minitest::Test
  PERIOD = 60
  START = 1_000.0
  WINDOW_RESET = 20
  SECRET_URL = "redis://:s3cret@127.0.0.1:%<port>d/0"

  # Raises the way redis-client does when the server is down.
  class UnreachableClient
    def call(*)
      raise ::RedisClient::CannotConnectError, "connection refused"
    end
  end

  class ExhaustedPoolClient
    def call(*)
      raise ConnectionPool::TimeoutError, "timed out"
    end
  end

  def setup
    @now = START
    @clock = -> { @now }
    @log = StringIO.new
  end

  def test_allow_lets_the_request_through_with_zero_count
    store = build_store(UnreachableClient.new)

    assert_equal [0, WINDOW_RESET], store.increment("client", PERIOD)
  end

  def test_allow_logs_once_per_window
    store = build_store(UnreachableClient.new)
    3.times { store.increment("client", PERIOD) }
    assert_equal 1, @log.string.lines.size

    @now = START + PERIOD
    store.increment("client", PERIOD)
    assert_equal 2, @log.string.lines.size
  end

  def test_allow_log_names_the_error_class_and_not_its_message
    store = build_store(UnreachableClient.new)
    store.increment("client", PERIOD)

    assert_equal "Boto::Redis::RateLimitStore: Redis unavailable at custom client " \
                 "(RedisClient::CannotConnectError); allowing requests\n", @log.string
  end

  def test_exhausted_pool_counts_as_unavailable
    store = build_store(ExhaustedPoolClient.new, on_error: :deny)

    assert_raises(Boto::Error::ServiceUnavailable) { store.increment("client", PERIOD) }
  end

  def test_deny_raises_service_unavailable
    store = build_store(UnreachableClient.new, on_error: :deny)

    error = assert_raises(Boto::Error::ServiceUnavailable) { store.increment("client", PERIOD) }
    assert_equal "rate limit store unavailable", error.detail
    assert_equal 503, error.status
  end

  def test_url_password_never_reaches_log_errors_or_inspect
    port = closed_port
    allow = build_url_store(port, timeout: 0.05, logger: @log)
    deny = build_url_store(port, timeout: 0.05, on_error: :deny)

    allow.increment("client", PERIOD)
    error = assert_raises(Boto::Error::ServiceUnavailable) { deny.increment("client", PERIOD) }

    assert_includes @log.string, "127.0.0.1:#{port}"
    refute_includes @log.string, "s3cret"
    refute_includes error.message, "s3cret"
    refute_includes allow.inspect, "s3cret"
    refute_includes allow.inspect, "redis://"
  end

  def test_lambda_url_is_read_once
    reads = 0
    url = -> { reads += 1; format(SECRET_URL, port: closed_port) }
    store = Boto::Redis::RateLimitStore.new(url: url, timeout: 0.05, logger: @log, clock: @clock)
    store.increment("client", PERIOD)
    store.increment("client", PERIOD)

    assert_equal 1, reads
  end

  private

  def build_store(client, **options)
    Boto::Redis::RateLimitStore.new(client: client, logger: @log, clock: @clock, **options)
  end

  def build_url_store(port, **options)
    Boto::Redis::RateLimitStore.new(url: format(SECRET_URL, port: port), clock: @clock, **options)
  end

  # A port nobody listens on, so connecting fails at once without touching the network.
  def closed_port
    server = TCPServer.new("127.0.0.1", 0)
    server.addr[1].tap { server.close }
  end
end
