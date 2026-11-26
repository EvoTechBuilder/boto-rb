# frozen_string_literal: true

module Boto
  class IsolationError < StandardError
    FIX_PREFIX = "Fix: boto ref"
    NAMESPACE_FIX_PREFIX = "Fix: move them under"

    attr_reader :violations

    def initialize(violations)
      @violations = violations.dup.freeze
      super(build_message(violations))
    end

    private

    def build_message(violations)
      violations.group_by(&:project).flat_map { |project, items| project_blocks(project, items) }.join("\n")
    end

    def project_blocks(project, items)
      reference, namespace = items.partition { _1.is_a?(Isolation::Violation) }
      blocks = [reference_block(project, reference), namespace_block(project, namespace)]
      blocks.compact
    end

    def reference_block(project, items)
      return if items.empty?

      header = %(project "#{project}" uses projects it does not reference:)
      lines = [header, *items.map { violation_line(_1) }, *fix_lines(project, items)]
      lines.join("\n")
    end

    def namespace_block(project, items)
      return if items.empty?

      namespace = items.first.namespace
      header = %(project "#{project}" declares constants outside its namespace #{namespace}:)
      lines = [header, *items.map { namespace_line(_1) }, "#{NAMESPACE_FIX_PREFIX} #{namespace}::"]
      lines.join("\n")
    end

    def namespace_line(violation)
      "  #{violation.path}:#{violation.line}  #{violation.constant}"
    end

    def violation_line(violation)
      "  #{violation.path}:#{violation.line}  #{violation.constant}  (#{violation.missing_ref} is not in refs)"
    end

    def fix_lines(project, items)
      items.map(&:missing_ref).uniq.map { "#{FIX_PREFIX} #{project} #{_1}" }
    end
  end
end
