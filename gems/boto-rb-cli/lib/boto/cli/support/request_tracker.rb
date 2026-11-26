# frozen_string_literal: true

require "set"

module Boto
  module CLI
    # Tracks the requests being served, so a drain knows when it is done and can cut the ones left over.
    class RequestTracker
      CUT_MESSAGE = "Cut by shutdown"

      def initialize
        @tasks = Set.new
      end

      def count = @tasks.size

      def wrap(app)
        ->(env) { track { app.call(env) } }
      end

      # Async defers `Task#stop` while a response is being written, so a cut raises into the request's fiber
      # directly, the same way `Task#cancel` does once the deferral is over.
      def cut_all
        @tasks.dup.each { |task| Fiber.scheduler.raise(task.fiber, Async::Cancel, CUT_MESSAGE) }
      end

      private

      def track
        task = Async::Task.current
        @tasks << task
        yield
      ensure
        @tasks.delete(task)
      end
    end
  end
end
