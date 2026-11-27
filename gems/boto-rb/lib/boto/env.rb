# frozen_string_literal: true

module Boto
  # Read-only view over stacked layers of variables. The strongest layer (first) wins.
  class Env
    def initialize(*layers)
      @values = merge_layers(layers).freeze
      freeze
    end

    def fetch(key, ...) = @values.fetch(key.to_s, ...)

    def [](key) = @values[key.to_s]

    def key?(key) = @values.key?(key.to_s)

    def to_h = @values

    private

    # Copies every layer into a new Hash, so the caller's Hashes (ENV included) are never frozen.
    def merge_layers(layers)
      layers.reverse_each.with_object({}) { |layer, merged| merged.merge!(layer) }
    end
  end
end
