# frozen_string_literal: true

module Boto
  module CLI
    # Usage error: its message is shown to the user as-is.
    class Error < StandardError; end
  end
end
