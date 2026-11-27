# frozen_string_literal: true

module Boto
  module Database
    # Raised when the :database plugin cannot connect. Its message never carries the URL.
    class ConnectionError < StandardError; end
  end
end
