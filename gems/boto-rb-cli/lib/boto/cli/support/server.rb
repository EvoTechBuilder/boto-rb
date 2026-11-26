# frozen_string_literal: true

require "async"
require "async/http/endpoint"
require "falcon/server"

module Boto
  module CLI
    # Serves one Rack app per port, all of them inside a single Async reactor.
    class Server
      DEFAULT_HOST = "127.0.0.1"
      MONOTONIC_CLOCK = -> { Process.clock_gettime(Process::CLOCK_MONOTONIC) }
      NEVER = -> { false }
      POLL_INTERVAL = 0.02

      attr_reader :apps_by_port, :host

      def initialize(apps_by_port, host: DEFAULT_HOST, clock: MONOTONIC_CLOCK)
        @apps_by_port = apps_by_port
        @host = host
        @clock = clock
        @tracker = RequestTracker.new
        @listeners = []
        @server_tasks = []
        @closing = false
      end

      # Blocks until the server stops. The block runs as a task inside the reactor, so it can call #drain.
      def run
        Async do |task|
          apps_by_port.each { |port, app| task.async { listen(app, port) } }
          task.async { yield } if block_given?
        end
      end

      # Stops accepting connections, then waits up to `timeout` for the requests in flight. Returns true when
      # they all finished in time; otherwise cuts the ones still running. Call it inside the reactor.
      def drain(delay:, timeout:, interrupted: NEVER)
        apps_by_port.each_value { |app| app.drain! if app.respond_to?(:drain!) }
        pause(delay, interrupted)
        close_listeners
        drained = wait_for_requests(timeout, interrupted)
        @tracker.cut_all unless drained
        stop_servers
        drained
      end

      private

      # Binding yields to the reactor (address resolution on Ruby 3.4), so a drain can run before the listener
      # or the server task is registered; each is closed here when that happened.
      def listen(app, port)
        endpoint = Async::HTTP::Endpoint.parse("http://#{host}:#{port}")
        listener = endpoint.bound
        @listeners << listener
        return listener.close if @closing

        server_task = falcon_server(app, endpoint, listener).run
        @server_tasks << server_task
        server_task.stop if @closing
        server_task.wait
      rescue IOError
        # Closing the listener is how drain ends the accept loop; any other IOError is a real failure.
        raise unless @closing
      end

      # Falcon's HTTP cache is on by default and would replay GET responses without reaching the app,
      # skipping auth, rate limits and per-user data; an API server must not cache, so it is disabled.
      def falcon_server(app, endpoint, listener)
        middleware = Falcon::Server.rack_middleware(@tracker.wrap(app), cache: false)
        Falcon::Server.new(middleware, listener, protocol: endpoint.protocol, scheme: endpoint.scheme)
      end

      def close_listeners
        @closing = true
        @listeners.each(&:close)
      end

      # Once the requests are done, the server tasks are stopped explicitly: on Ruby 3.4 the accept loop does
      # not end when its listener closes, and keep-alive connections would hold them open on any version.
      def stop_servers
        @server_tasks.each(&:stop)
      end

      def pause(seconds, interrupted)
        deadline = now + seconds
        sleep POLL_INTERVAL until interrupted.call || now >= deadline
      end

      def wait_for_requests(timeout, interrupted)
        deadline = now + timeout
        sleep POLL_INTERVAL until @tracker.count.zero? || interrupted.call || now >= deadline
        @tracker.count.zero?
      end

      def now = @clock.call
    end
  end
end
