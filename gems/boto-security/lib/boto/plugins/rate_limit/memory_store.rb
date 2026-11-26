# frozen_string_literal: true

module Boto
  module Plugins
    class RateLimit < Boto::Plugin
      # In-process fixed-window counter. Each store is meant for a single period and keeps counters
      # only for the current window, capped at max_keys keys per window (oldest evicted first).
      # Evicted keys restart at zero, so a client with many IPs can reset an old key's count.
      # Counts are lost on restart and are not shared between processes.
      class MemoryStore
        MIN_RESET_SECONDS = 1
        DEFAULT_MAX_KEYS = 100_000

        def initialize(clock:, max_keys: DEFAULT_MAX_KEYS)
          @clock = clock
          @max_keys = positive_integer!(max_keys)
          @mutex = Mutex.new
          @windows = {}
        end

        # Returns [count, reset_in]: the requests counted for key in the current window,
        # and the whole seconds left until that window ends.
        def increment(key, period)
          now = @clock.call
          window = (now / period).floor
          @mutex.synchronize do
            drop_windows_before(window)
            count = count_request((@windows[window] ||= {}), key)
            [count, reset_in(now, window, period)]
          end
        end

        # Number of live counters (one per key in each stored window). Useful for tests and monitoring.
        def size
          @mutex.synchronize { @windows.sum { |_window, counts| counts.size } }
        end

        private

        def positive_integer!(value)
          return value if value.is_a?(Integer) && value.positive?

          raise ArgumentError, "max_keys must be a positive Integer, got #{value.inspect}"
        end

        def drop_windows_before(window)
          @windows.delete_if { |stored, _counts| stored < window }
        end

        # Hash keeps insertion order, so shift removes the oldest key in O(1).
        def count_request(counts, key)
          if counts.key?(key)
            counts[key] += 1
          else
            counts.shift if counts.size >= @max_keys
            counts[key] = 1
          end
        end

        def reset_in(now, window, period)
          window_end = (window + 1) * period
          [(window_end - now).ceil, MIN_RESET_SECONDS].max
        end
      end
    end
  end
end
