# frozen_string_literal: true

module Boto
  module Database
    # Databases of the running projects, keyed by namespace. The :database plugin fills it at start and
    # empties it at stop, so it only changes at boot and shutdown; the lock covers the hand-off between threads.
    class Connections
      @registry = {}
      @lock = Mutex.new

      class << self
        def register(namespace, database)
          @lock.synchronize { @registry[namespace] = database }
        end

        def unregister(namespace)
          @lock.synchronize { @registry.delete(namespace) }
        end

        def registered?(namespace)
          @lock.synchronize { @registry.key?(namespace) }
        end

        def for(namespace)
          database = @lock.synchronize { @registry[namespace] }
          database || raise(MissingDatabaseError, namespace)
        end
      end
    end
  end
end
