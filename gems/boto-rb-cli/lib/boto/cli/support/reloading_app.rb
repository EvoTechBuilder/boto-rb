# frozen_string_literal: true

module Boto
  module CLI
    # The Rack app the Server holds for one port: each request goes to the app the Reloader has at that moment.
    class ReloadingApp
      def initialize(reloader, port)
        @reloader = reloader
        @port = port
      end

      def call(env)
        @reloader.current(@port).call(env)
      end

      def drain!
        @reloader.drain!
      end
    end
  end
end
