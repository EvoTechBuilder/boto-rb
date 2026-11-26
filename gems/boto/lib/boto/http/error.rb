# frozen_string_literal: true

require "rack/utils"

module Boto
  # Base error. Each subclass maps to an HTTP status and renders as a problem response.
  class Error < StandardError
    STATUS = 500
    NO_HEADERS = {}.freeze

    attr_reader :detail

    def initialize(detail = nil)
      @detail = detail
      super(detail || Rack::Utils::HTTP_STATUS_CODES.fetch(self.class::STATUS))
    end

    def status
      self.class::STATUS
    end

    def errors
      nil
    end

    def headers
      NO_HEADERS
    end

    def to_response
      Problem.response(status, detail: detail, errors: errors, headers: headers)
    end

    class BadRequest < Error
      STATUS = 400
    end

    class NotFound < Error
      STATUS = 404
    end

    class MethodNotAllowed < Error
      STATUS = 405

      attr_reader :allowed

      def initialize(allowed, detail = nil)
        @allowed = allowed
        super(detail)
      end

      def headers
        { "allow" => allowed.join(", ") }
      end
    end

    class PayloadTooLarge < Error
      STATUS = 413
    end

    class Unprocessable < Error
      STATUS = 422

      attr_reader :errors

      def initialize(errors, detail = nil)
        @errors = errors
        super(detail)
      end
    end

    class Unauthorized < Error
      STATUS = 401

      attr_reader :challenge

      def initialize(challenge = nil, detail = nil)
        @challenge = challenge
        super(detail)
      end

      def headers
        challenge ? { "www-authenticate" => challenge } : NO_HEADERS
      end
    end

    class Forbidden < Error
      STATUS = 403
    end

    class TooManyRequests < Error
      STATUS = 429

      attr_reader :retry_after

      def initialize(retry_after, detail = nil)
        @retry_after = retry_after
        super(detail)
      end

      def headers
        { "retry-after" => retry_after.to_s }
      end
    end
  end
end
