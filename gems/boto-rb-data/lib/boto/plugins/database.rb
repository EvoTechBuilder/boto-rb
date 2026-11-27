# frozen_string_literal: true

require "sequel"
require "uri"

module Boto
  module Plugins
    # Connects the project to its database with Sequel. The connection is registered under the project
    # namespace at start, and it answers the /health/ready probe with a test query.
    class Database < Boto::Plugin
      DEFAULT_POOL = 5
      MASK = "***"
      UNPARSEABLE_URL = "[unparseable url]"
      FIBER_EXTENSION = :fiber_concurrency
      HEALTH_CHECK = :database
      URL_MESSAGE = "database: url must be a non-empty String or a callable that returns one"
      POOL_MESSAGE = "database: pool must be a positive Integer"

      # No #call: the plugin only has a lifecycle (connect, disconnect, health), so the core leaves it out of
      # every request stack.

      def attach(app)
        @namespace = Object.const_get(app.title)
      end

      def start
        Sequel.extension FIBER_EXTENSION
        database = connect
        check_repositories(database)
        @database = database
        Boto::Database::Connections.register(@namespace, @database)
      end

      # Safe to call twice: the second call finds nothing left to close.
      def stop
        return unless @database

        Boto::Database::Connections.unregister(@namespace)
        @database.disconnect
        @database = nil
      end

      def health_checks
        { HEALTH_CHECK => -> { @database.test_connection } }
      end

      def inspect
        "#<#{self.class.name} url=#{masked_url} pool=#{@pool}>"
      end

      private

      def configure(url:, pool: DEFAULT_POOL, logger: nil)
        @url = resolve_url(url)
        @pool = validate_pool(pool)
        @logger = logger
      end

      # A callable is resolved here, at boot, so a missing secret (KeyError) stops the boot.
      def resolve_url(url)
        value = url.respond_to?(:call) ? url.call : url
        return value if value.is_a?(String) && !value.strip.empty?

        raise ArgumentError, URL_MESSAGE
      end

      def validate_pool(pool)
        return pool if pool.is_a?(Integer) && pool.positive?

        raise ArgumentError, POOL_MESSAGE
      end

      # Runs before the connection is registered, so a failed check leaves no connection behind.
      def check_repositories(database)
        repositories.each { _1.check!(database) }
      rescue StandardError
        database.disconnect
        raise
      end

      # Only the classes already loaded: the core eager loads the project code before it starts the plugins.
      def repositories
        prefix = "#{@namespace.name}::"
        Boto::Repository.subclasses.select do |repository|
          repository.name.to_s.start_with?(prefix) && repository.declared?
        end
      end

      def connect
        Sequel.connect(@url, max_connections: @pool, test: true, logger: @logger)
      rescue StandardError => error
        # cause: nil keeps the driver error, which may print the URL, out of the boot report.
        raise Boto::Database::ConnectionError, "database: could not connect (#{error.class})", cause: nil
      end

      def masked_url
        uri = URI.parse(@url)
        uri.password = MASK if uri.password
        uri.to_s
      rescue URI::InvalidURIError
        UNPARSEABLE_URL
      end
    end
  end
end
