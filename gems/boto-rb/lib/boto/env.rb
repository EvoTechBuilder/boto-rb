# frozen_string_literal: true

module Boto
  # Read-only view over stacked layers of variables. The strongest layer (first) wins.
  class Env
    PROCESS_SOURCE = "process"

    # sources: key => where its effective value came from (PROCESS_SOURCE or a file path).
    # file_keys: keys defined by some .env file, even when a higher layer overrides them.
    def initialize(*layers, sources: {}, file_keys: [])
      @values = merge_layers(layers).freeze
      @sources = sources.to_h { |key, source| [key.to_s, source] }.freeze
      @file_keys = file_keys.map(&:to_s).sort.freeze
      freeze
    end

    def fetch(key, ...) = @values.fetch(key.to_s, ...)

    def [](key) = @values[key.to_s]

    def key?(key) = @values.key?(key.to_s)

    def source(key) = key?(key) ? @sources[key.to_s] : nil

    attr_reader :file_keys

    def to_h = @values

    private

    # Copies every layer into a new Hash, so the caller's Hashes (ENV included) are never frozen.
    def merge_layers(layers)
      layers.reverse_each.with_object({}) { |layer, merged| merged.merge!(layer) }
    end
  end
end
