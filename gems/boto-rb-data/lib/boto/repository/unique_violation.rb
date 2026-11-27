# frozen_string_literal: true

module Boto
  class Repository
    # Raised by create, update and delete when a unique constraint fails. The driver error is the cause.
    class UniqueViolation < StandardError; end
  end
end
