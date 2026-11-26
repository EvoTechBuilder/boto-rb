# frozen_string_literal: true

require "prism"

module Boto
  module CLI
    # Adds references to a Botofile's source text, touching only the inserted fragment.
    module BotofileEditor
      PROJECT_METHOD = :project
      REFS_KEY = "refs"
      WORD_ARRAY_OPENINGS = %w[%w %i].freeze
      SYNTAX_ERROR_MESSAGE = "Botofile has syntax errors"

      def self.add_ref(source, project:, ref:)
        call = find_project_call(parse(source), project)
        option = refs_option(call)
        return splice(source, call.arguments.location.end_offset, ", #{REFS_KEY}: %w[#{ref}]") unless option

        array = refs_array(option, project, ref)
        splice(source, array.closing_loc.start_offset, array_insertion(array, ref))
      end

      def self.parse(source)
        result = Prism.parse(source)
        raise Error, SYNTAX_ERROR_MESSAGE if result.failure?

        result.value
      end

      def self.find_project_call(program, project)
        call = program.statements.body.find { |node| project_call?(node, project) }
        raise Error, %(project "#{project}" not found in Botofile) unless call

        call
      end

      def self.project_call?(node, project)
        node.is_a?(Prism::CallNode) && node.receiver.nil? && node.name == PROJECT_METHOD &&
          string_named?(first_argument(node), project)
      end

      def self.first_argument(call)
        call.arguments&.arguments&.first
      end

      def self.string_named?(node, name)
        node.is_a?(Prism::StringNode) && node.unescaped == name
      end

      def self.refs_option(call)
        last = call.arguments.arguments.last
        return unless last.is_a?(Prism::KeywordHashNode)

        last.elements.find { |element| refs_assoc?(element) }
      end

      def self.refs_assoc?(element)
        element.is_a?(Prism::AssocNode) && element.key.is_a?(Prism::SymbolNode) && element.key.unescaped == REFS_KEY
      end

      def self.refs_array(option, project, ref)
        array = option.value
        raise Error, "refs must be a literal array" unless array.is_a?(Prism::ArrayNode)
        raise Error, %("#{project}" already references "#{ref}") if duplicate?(array, ref)

        array
      end

      def self.array_insertion(array, ref)
        word = word_array?(array)
        element = word ? ref : %("#{ref}")
        return element if array.elements.empty?

        "#{word ? " " : ", "}#{element}"
      end

      def self.word_array?(array)
        array.opening_loc.slice.start_with?(*WORD_ARRAY_OPENINGS)
      end

      def self.duplicate?(array, ref)
        array.elements.any? { |element| element.respond_to?(:unescaped) && element.unescaped == ref }
      end

      # Prism offsets are byte offsets, so splice on bytes and restore the source encoding.
      def self.splice(source, offset, text)
        (source.byteslice(0, offset).b + text.b + source.byteslice(offset..).b).force_encoding(source.encoding)
      end
    end
  end
end
