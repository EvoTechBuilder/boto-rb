# frozen_string_literal: true

require "json"
require "rack/utils"

module Boto
  # Builds RFC 9457 "application/problem+json" Rack responses.
  module Problem
    CONTENT_TYPE = "application/problem+json"

    def self.response(status, detail: nil, errors: nil, headers: {})
      body = JSON.generate(compact_body(status, detail, errors))
      [status, { "content-type" => CONTENT_TYPE }.merge(headers), [body]]
    end

    def self.compact_body(status, detail, errors)
      {
        type: "about:blank",
        title: Rack::Utils::HTTP_STATUS_CODES.fetch(status),
        status: status,
        detail: detail,
        errors: errors
      }.compact
    end
    private_class_method :compact_body
  end
end
