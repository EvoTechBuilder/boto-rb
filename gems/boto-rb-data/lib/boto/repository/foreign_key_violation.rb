# frozen_string_literal: true

module Boto
  class Repository
    # Raised by create, update and delete when a foreign key constraint fails. The driver error is the cause.
    class ForeignKeyViolation < StandardError; end
  end
end
