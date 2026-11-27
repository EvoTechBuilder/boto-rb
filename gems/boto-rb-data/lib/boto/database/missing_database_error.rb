# frozen_string_literal: true

module Boto
  module Database
    # Raised when a project asks for its database but its config/app.rb does not enable :database.
    class MissingDatabaseError < StandardError
      def initialize(namespace)
        super("#{namespace} has no database: add app.use :database, url: ... to its config/app.rb")
      end
    end
  end
end
