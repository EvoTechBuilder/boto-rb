# frozen_string_literal: true

require "uri"

module Boto
  module Redis
    # Fixed-window counter in Redis, shared by every process that uses the same Redis.
    # The URL never reaches logs, errors or inspect: only host:port is described.
    class RateLimitStore
      DEFAULT_PREFIX = "boto:rate_limit"
      DEFAULT_TIMEOUT = 0.1
      # Measured on Falcon with wrk -c50: 5 -> ~9.1k req/s, 20 -> ~11.1k with the best p99; more gains nothing and worsens p99.
      # Connections are created on demand, so an idle pool costs nothing.
      DEFAULT_POOL_SIZE = 20
      DEFAULT_CLOCK = -> { Process.clock_gettime(Process::CLOCK_REALTIME) }.freeze
      ON_ERROR_MODES = %i[allow deny].freeze
      FAILURES = [::RedisClient::Error, ConnectionPool::TimeoutError].freeze
      CUSTOM_CLIENT = "custom client"
      UNAVAILABLE_MESSAGE = "rate limit store unavailable"
      MIN_RESET_SECONDS = 1
      MIN_TTL_MS = 1
      MS_PER_SECOND = 1000

      def initialize(url: nil, client: nil, prefix: DEFAULT_PREFIX, timeout: DEFAULT_TIMEOUT,
                     pool_size: DEFAULT_POOL_SIZE, on_error: :allow, logger: $stderr, clock: DEFAULT_CLOCK)
        url = url.call if url.respond_to?(:call)
        validate_source!(url, client)
        validate_options!(prefix, timeout, pool_size, on_error)

        @prefix = prefix
        @on_error = on_error
        @logger = logger
        @clock = clock
        @outage_mutex = Mutex.new
        @outage_window = nil
        @key_prefixes = {}
        @owns_client = !url.nil?
        @closed = false
        @client, @endpoint = url ? connect(url, timeout, pool_size) : [client, CUSTOM_CLIENT]
      end

      # Returns [count, reset_in]: requests counted for key in the current window and whole seconds until it ends.
      def increment(key, period)
        now = @clock.call
        window = window_of(now, period)
        count, pttl = Script.run(@client, counter_key(key, period, window), ms_until_window_end(now, window, period))
        [count, seconds_from_ms(pttl)]
      rescue *FAILURES => error
        handle_failure(error, now, period)
      end

      def inspect
        "#<#{self.class.name} endpoint=#{@endpoint} prefix=#{@prefix} on_error=#{@on_error}>"
      end

      # With on_error: :deny, an outage answers 503 (see handle_failure).
      def error_statuses
        @on_error == :deny ? [::Boto::Error::ServiceUnavailable::STATUS] : []
      end

      # An injected client belongs to the caller, so only the pool built from url: is closed here.
      def close
        return if @closed

        @closed = true
        @client.close if @owns_client
      end

      private

      def validate_source!(url, client)
        raise ArgumentError, "pass exactly one of url: or client:" if url.nil? == client.nil?
        raise ArgumentError, "url must be a String" unless url.nil? || url.is_a?(String)
      end

      def validate_options!(prefix, timeout, pool_size, on_error)
        raise ArgumentError, "prefix must be a non-empty String" unless prefix.is_a?(String) && !prefix.empty?
        raise ArgumentError, "timeout must be a positive Numeric" unless timeout.is_a?(Numeric) && timeout.positive?
        raise ArgumentError, "pool_size must be a positive Integer" unless pool_size.is_a?(Integer) && pool_size.positive?
        raise ArgumentError, "on_error must be one of #{ON_ERROR_MODES.inspect}" unless ON_ERROR_MODES.include?(on_error)
      end

      # Returns [pool, endpoint]. The pool lets concurrent fibers and threads each use their own connection.
      # endpoint_of runs first: redis-client parses the URL too, and its parse errors echo the whole URL.
      def connect(url, timeout, pool_size)
        endpoint = endpoint_of(url)
        config = ::RedisClient.config(url: url, connect_timeout: timeout, read_timeout: timeout, write_timeout: timeout)
        [config.new_pool(size: pool_size, timeout: timeout), endpoint]
      end

      # Raises without the original message, which may contain the URL.
      def endpoint_of(url)
        uri = URI(url)
        uri.host ? "#{uri.host}:#{uri.port}" : uri.scheme
      rescue URI::Error
        raise ArgumentError, "url is not a valid Redis URL"
      end

      def window_of(now, period)
        (now / period).floor
      end

      def counter_key(key, period, window)
        "#{key_prefix(period, window)}#{key}"
      end

      # Cached per period while the window is the same. Two threads may rebuild it at once; both get the same value.
      def key_prefix(period, window)
        cached_window, prefix = @key_prefixes[period]
        return prefix if cached_window == window

        prefix = "#{@prefix}:#{period}:#{window}:".freeze
        @key_prefixes[period] = [window, prefix]
        prefix
      end

      def ms_until_window_end(now, window, period)
        [((window + 1) * period - now) * MS_PER_SECOND, MIN_TTL_MS].max.ceil
      end

      def reset_in(now, window, period)
        [((window + 1) * period - now).ceil, MIN_RESET_SECONDS].max
      end

      def seconds_from_ms(pttl)
        [(pttl / MS_PER_SECOND.to_f).ceil, MIN_RESET_SECONDS].max
      end

      def handle_failure(error, now, period)
        raise ::Boto::Error::ServiceUnavailable.new(UNAVAILABLE_MESSAGE) if @on_error == :deny

        window = window_of(now, period)
        log_outage_once(error, window)
        [0, reset_in(now, window, period)]
      end

      def log_outage_once(error, window)
        return unless first_outage_in?(window)

        @logger.puts("Boto::Redis::RateLimitStore: Redis unavailable at #{@endpoint} (#{error.class}); allowing requests")
      end

      def first_outage_in?(window)
        @outage_mutex.synchronize do
          first = @outage_window != window
          @outage_window = window
          first
        end
      end
    end
  end
end
