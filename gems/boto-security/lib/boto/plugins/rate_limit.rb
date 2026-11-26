# frozen_string_literal: true

require "ipaddr"

module Boto
  module Plugins
    # Limits how many requests a client key may make per fixed window. The default key is the
    # client IP, which X-Forwarded-For can only change when the direct peer is a trusted proxy.
    class RateLimit < Boto::Plugin
      scope :endpoint

      DEFAULT_CLOCK = -> { Process.clock_gettime(Process::CLOCK_MONOTONIC) }.freeze
      LIMIT_HEADER = "ratelimit-limit"
      REMAINING_HEADER = "ratelimit-remaining"
      RESET_HEADER = "ratelimit-reset"

      def call(env, app)
        count, reset_in = @store.increment(client_key(env), @period)
        status, headers, body = count > @limit ? too_many_requests(reset_in) : app.call(env)
        [status, with_rate_headers(headers, count, reset_in), body]
      end

      private

      def configure(limit:, period:, key: nil, trusted_proxies: [], store: nil, clock: nil)
        @limit = positive_integer!(limit, :limit)
        @period = positive_integer!(period, :period)
        @key = callable_key!(key)
        @trusted_proxies = parse_proxies(trusted_proxies)
        @store = store || MemoryStore.new(clock: clock || DEFAULT_CLOCK)
      end

      def positive_integer!(value, name)
        return value if value.is_a?(Integer) && value.positive?

        raise ArgumentError, "#{name} must be a positive Integer, got #{value.inspect}"
      end

      def callable_key!(key)
        return key if key.nil? || key.respond_to?(:call)

        raise ArgumentError, "key must be nil or a callable, got #{key.inspect}"
      end

      def parse_proxies(entries)
        raise ArgumentError, "trusted_proxies must be an Array" unless entries.is_a?(Array)

        entries.map { |entry| IPAddr.new(entry) }
      end

      def too_many_requests(reset_in)
        Boto::Error::TooManyRequests.new(reset_in).to_response
      end

      def with_rate_headers(headers, count, reset_in)
        headers = headers.dup if headers.frozen?
        headers[LIMIT_HEADER] = @limit.to_s
        headers[REMAINING_HEADER] = [@limit - count, 0].max.to_s
        headers[RESET_HEADER] = reset_in.to_s
        headers
      end

      def client_key(env)
        @key ? @key.call(env) : client_ip(env)
      end

      def client_ip(env)
        remote = env["REMOTE_ADDR"]
        forwarded = env["HTTP_X_FORWARDED_FOR"]
        return remote unless forwarded && trusted?(remote)

        forwarded_client(forwarded.split(",").map(&:strip), remote)
      end

      # The rightmost hop that is not a trusted proxy is the client; falls back to the leftmost hop.
      def forwarded_client(hops, remote)
        hops.reverse.find { |hop| !trusted?(hop) } || hops.first || remote
      end

      def trusted?(address)
        ip = parse_ip(address)
        !ip.nil? && @trusted_proxies.any? { |proxy| proxy.include?(ip) }
      end

      def parse_ip(address)
        IPAddr.new(address.to_s)
      rescue IPAddr::Error
        nil
      end
    end
  end
end
