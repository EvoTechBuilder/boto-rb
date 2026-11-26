# frozen_string_literal: true

module Boto
  module Plugins
    class RateLimit < Boto::Plugin
      # In-process fixed-window counter. Each store is meant for a single period, and it only
      # keeps counters for the current window, so memory is bounded by the keys seen in it.
      # Counts are lost on restart and are not shared between processes.
      # shortcut: keys within one window are not capped (a flood of distinct IPs grows it until the window ends);
      # add a cap or move to the Redis store when a service needs it.
      class MemoryStore
        MIN_RESET_SECONDS = 1

        def initialize(clock:)
          @clock = clock
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
            count = (@windows[window] ||= Hash.new(0))[key] += 1
            [count, reset_in(now, window, period)]
          end
        end

        # Number of live counters (one per key in each stored window). Useful for tests and monitoring.
        def size
          @mutex.synchronize { @windows.sum { |_window, counts| counts.size } }
        end

        private

        def drop_windows_before(window)
          @windows.delete_if { |stored, _counts| stored < window }
        end

        def reset_in(now, window, period)
          window_end = (window + 1) * period
          [(window_end - now).ceil, MIN_RESET_SECONDS].max
        end
      end
    end
  end
end
