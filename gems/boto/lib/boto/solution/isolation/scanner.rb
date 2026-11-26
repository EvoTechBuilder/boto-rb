# frozen_string_literal: true

require "prism"
require "set"

module Boto
  module Isolation
    # Lists the constants a Ruby file uses and declares, without running it.
    class Scanner
      NAMESPACE_SEPARATOR = "::"

      class SyntaxError < StandardError
        attr_reader :path, :line

        def initialize(path, line, reason)
          @path = path
          @line = line
          super("#{path}:#{line}: #{reason}")
        end
      end

      Use = Data.define(:constant, :root, :line)
      Scan = Data.define(:used, :declared)

      def self.scan(source, path:)
        result = Prism.parse(source)
        raise_on_syntax_error(result, path)
        collector = Collector.new
        collector.visit(result.value)
        Scan.new(used: collector.used.freeze, declared: collector.declared.freeze)
      end

      # Names of a constant reference such as `A::B`, or nil when the parent is an expression.
      def self.segments(node)
        case node
        when Prism::ConstantReadNode then [node.name.to_s]
        when Prism::ConstantPathNode then path_segments(node)
        end
      end

      def self.path_segments(node)
        name = node.name.to_s
        return [name] if node.parent.nil?

        prefix = segments(node.parent)
        prefix && [*prefix, name]
      end

      def self.raise_on_syntax_error(result, path)
        error = result.errors.first
        return unless error

        raise SyntaxError.new(path, error.location.start_line, error.message)
      end

      private_class_method :path_segments, :raise_on_syntax_error

      class Collector < Prism::Visitor
        attr_reader :used, :declared

        def initialize
          super
          @used = []
          @declared = Set.new
          @depth = 0
        end

        def visit_constant_read_node(node)
          record_use([node.name.to_s], node.location.start_line)
        end

        # Only the outermost path is a use; its inner segments are not visited again.
        def visit_constant_path_node(node)
          segments = Scanner.segments(node)
          return visit(node.parent) unless segments

          record_use(segments, node.location.start_line)
        end

        def visit_class_node(node)
          declare(node.constant_path)
          visit(node.superclass)
          nested { visit(node.body) }
        end

        def visit_module_node(node)
          declare(node.constant_path)
          nested { visit(node.body) }
        end

        def visit_constant_write_node(node)
          @declared << node.name.to_s
          visit(node.value)
        end

        # `Billing::Rate = 1` declares only `Rate`; `Billing` is still a reference.
        def visit_constant_path_write_node(node)
          @declared << node.target.name.to_s
          visit(node.target.parent)
          visit(node.value)
        end

        private

        # At the top level the first segment names an existing namespace, so it is a use:
        # `class Billing::Invoice` in another project reopens Billing and must not hide its uses.
        # Inside a class/module body every segment is a nested declaration (`module Orders; module Billing`).
        def declare(path_node)
          segments = Scanner.segments(path_node)
          return visit(path_node) unless segments

          if @depth.zero?
            record_use([segments.first], path_node.location.start_line)
            @declared.merge(segments.drop(1))
          else
            @declared.merge(segments)
          end
        end

        def nested
          @depth += 1
          yield
        ensure
          @depth -= 1
        end

        def record_use(segments, line)
          @used << Use.new(constant: segments.join(NAMESPACE_SEPARATOR), root: segments.first, line: line)
        end
      end
      private_constant :Collector
    end
  end
end
