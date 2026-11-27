# frozen_string_literal: true

module Boto
  class Env
    # Messages carry the file, the line and the key, never the value.
    class ParseError < StandardError; end
  end
end
