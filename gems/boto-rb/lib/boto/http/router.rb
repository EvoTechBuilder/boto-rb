# frozen_string_literal: true

require "rack/utils"

module Boto
  # Radix-style router: static segments win over dynamic ones, with backtracking.
  class Router
    # A plain class instead of Data: Data.new builds an internal Hash on every call.
    class Match
      attr_reader :target, :params

      def initialize(target, params)
        @target = target
        @params = params
        freeze
      end
    end

    class DuplicateRouteError < StandardError; end

    class Node
      attr_reader :static, :handlers
      attr_accessor :dynamic

      def initialize
        @static = {}
        @dynamic = nil
        @handlers = {}
      end

      def freeze
        static.each_value(&:freeze)
        dynamic&.freeze
        handlers.freeze
        static.freeze
        super
      end
    end

    EMPTY_PARAMS = {}.freeze

    SEPARATOR = "/"
    PERCENT = "%"
    DYNAMIC_PREFIX = ":"
    VERB_GET = "GET"
    VERB_HEAD = "HEAD"

    def initialize
      @root = Node.new
    end

    def add(verb, pattern, target)
      segments = segments_of(pattern)
      leaf = segments.reduce(@root) { |node, segment| child_for_add(node, segment) }
      raise DuplicateRouteError, "route #{verb} #{pattern} is already registered" if leaf.handlers.key?(verb)

      leaf.handlers[verb] = [target, param_names_of(segments).freeze]
      self
    end

    def compile
      @root.freeze
      self
    end

    def match(verb, path)
      values = []
      handler = resolve(@root, segments_of(path), 0, verb, values)
      Match.new(handler[0], params_for(handler[1], values)) if handler
    end

    def allowed_verbs(path)
      verbs = leaf_verbs(@root, segments_of(path), 0).uniq
      verbs << VERB_HEAD if verbs.include?(VERB_GET) && !verbs.include?(VERB_HEAD)
      verbs.sort
    end

    private

    # Walks the path by byte offsets so no intermediate arrays or empty strings are built.
    def segments_of(path)
      segments = []
      start = 0
      while start < path.bytesize
        separator = path.byteindex(SEPARATOR, start) || path.bytesize
        segments << path.byteslice(start, separator - start) if separator > start
        start = separator + SEPARATOR.bytesize
      end
      segments
    end

    # Rack's unescape is only needed when a percent-escape is present.
    def unescape(segment)
      segment.include?(PERCENT) ? Rack::Utils.unescape_path(segment) : segment
    end

    def dynamic_segment?(segment)
      segment.start_with?(DYNAMIC_PREFIX)
    end

    def param_names_of(segments)
      segments.filter_map { |segment| segment[1..].to_sym if dynamic_segment?(segment) }
    end

    def child_for_add(node, segment)
      if dynamic_segment?(segment)
        node.dynamic ||= Node.new
      else
        node.static[segment] ||= Node.new
      end
    end

    # Returns [target, param_names] for the leaf handling verb, filling values with captured segments.
    def resolve(node, segments, index, verb, values)
      return handler_for(node, verb) if index == segments.size

      segment = segments[index]
      handler = resolve_static(node, segment, segments, index, verb, values)
      handler || resolve_dynamic(node, segment, segments, index, verb, values)
    end

    def resolve_static(node, segment, segments, index, verb, values)
      child = node.static[segment]
      child && resolve(child, segments, index + 1, verb, values)
    end

    def resolve_dynamic(node, segment, segments, index, verb, values)
      return unless node.dynamic

      values.push(unescape(segment))
      handler = resolve(node.dynamic, segments, index + 1, verb, values)
      values.pop unless handler
      handler
    end

    def handler_for(node, verb)
      node.handlers[verb] || head_fallback(node, verb)
    end

    def head_fallback(node, verb)
      node.handlers[VERB_GET] if verb == VERB_HEAD
    end

    def params_for(names, values)
      return EMPTY_PARAMS if names.empty?

      # A while loop avoids the block and enumerator objects of each_with_index.
      params = {}
      index = 0
      while index < names.size
        params[names[index]] = values[index]
        index += 1
      end
      params
    end

    def leaf_verbs(node, segments, index)
      return node.handlers.keys if index == segments.size

      segment = segments[index]
      verbs = []
      child = node.static[segment]
      verbs.concat(leaf_verbs(child, segments, index + 1)) if child
      verbs.concat(leaf_verbs(node.dynamic, segments, index + 1)) if node.dynamic
      verbs
    end
  end
end
