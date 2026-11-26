# frozen_string_literal: true

require "json"

module Boto
  # Reads and parses JSON request bodies, rejecting bodies above a size limit.
  module RequestBody
    DEFAULT_LIMIT = 1_048_576
    EMPTY = {}.freeze
    JSON_MEDIA_TYPE = "application/json"
    JSON_SUFFIX = "+json"

    def self.parse(env, limit: DEFAULT_LIMIT)
      return EMPTY unless json_content_type?(env["CONTENT_TYPE"])

      check_declared_length(env["CONTENT_LENGTH"], limit)
      raw = read_body(env["rack.input"], limit)
      return EMPTY if raw.nil? || raw.empty?

      decode(raw)
    end

    def self.json_content_type?(content_type)
      media_type = content_type.to_s.partition(";").first.strip.downcase
      media_type == JSON_MEDIA_TYPE || media_type.end_with?(JSON_SUFFIX)
    end

    def self.check_declared_length(content_length, limit)
      return if content_length.nil?

      raise Boto::Error::PayloadTooLarge if content_length.to_i > limit
    end

    # Reads one byte past the limit so an oversized body is detected without buffering it whole.
    def self.read_body(input, limit)
      return if input.nil?

      raw = input.read(limit + 1)
      raise Boto::Error::PayloadTooLarge if raw && raw.bytesize > limit

      raw
    end

    def self.decode(raw)
      parsed = parse_json(raw)
      raise Boto::Error::BadRequest.new("JSON body must be an object") unless parsed.is_a?(Hash)

      parsed
    end

    def self.parse_json(raw)
      JSON.parse(raw)
    rescue JSON::ParserError
      raise Boto::Error::BadRequest.new("invalid JSON body")
    end

    private_class_method :json_content_type?, :check_declared_length, :read_body, :decode, :parse_json
  end
end
