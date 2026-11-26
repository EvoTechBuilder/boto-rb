# frozen_string_literal: true

require "date"
require "time"

module Boto
  module Types
    # Pure coercion functions. Each returns the coerced value, or nil when the input does not fit.
    # nil is a safe failure marker because no supported type coerces to nil.
    module Coercion
      INTEGER_FORMAT = /\A-?\d+\z/
      DATE_FORMAT = /\A\d{4}-\d{2}-\d{2}\z/
      TIME_FORMAT = /\A\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d+)?(Z|[+-]\d{2}:\d{2})\z/

      module_function

      def string(value)
        value if value.is_a?(String)
      end

      def integer(value)
        case value
        when Integer then value
        when String then value.to_i if INTEGER_FORMAT.match?(value)
        end
      end

      def float(value)
        case value
        when Integer, Float then value.to_f
        when String then Float(value, exception: false)
        end
      end

      def boolean(value)
        Boto::Boolean.coerce(value)
      rescue ArgumentError
        nil
      end

      def date(value)
        case value
        when Date then value
        when String then Date.iso8601(value) if DATE_FORMAT.match?(value)
        end
      rescue ArgumentError
        nil
      end

      # Time.iso8601 accepts a missing offset (local time), so the zone is checked by the pattern first.
      def time(value)
        case value
        when Time then value
        when String then Time.iso8601(value) if TIME_FORMAT.match?(value)
        end
      rescue ArgumentError
        nil
      end
    end
  end
end
