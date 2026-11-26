# frozen_string_literal: true

module Boto
  module CLI
    # Turns TERM and INT into something the reactor can wait on. The trap only writes a byte to a pipe,
    # because trap handlers must not run fiber code.
    class ShutdownSignal
      SIGNALS = %w[TERM INT].freeze
      BYTE = "x"

      def initialize(signals: SIGNALS)
        @signals = signals
        @reader, @writer = IO.pipe
        @received = 0
      end

      def repeated? = @received > 1

      # Fiber-aware: call it inside the reactor. Returns once one more signal arrived.
      def wait
        @reader.wait_readable
        @reader.read_nonblock(1, exception: false)
        nil
      end

      # Traps the signals only while the block runs. Single use: the pipe is closed at the end.
      def install
        previous = @signals.to_h { |name| [name, trap(name) { receive }] }
        yield
      ensure
        previous&.each { |name, handler| trap(name, handler) }
        @reader.close
        @writer.close
      end

      private

      def receive
        @received += 1
        @writer.write_nonblock(BYTE, exception: false)
      end
    end
  end
end
