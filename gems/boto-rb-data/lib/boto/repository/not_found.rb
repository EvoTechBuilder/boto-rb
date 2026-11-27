# frozen_string_literal: true

module Boto
  class Repository
    # Raised by find! when no row has the id.
    class NotFound < StandardError
      def initialize(entity, id)
        super("#{entity} #{id} not found")
      end
    end
  end
end
