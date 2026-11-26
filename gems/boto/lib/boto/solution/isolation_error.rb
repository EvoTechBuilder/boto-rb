# frozen_string_literal: true

module Boto
  class IsolationError < StandardError
    FIX_PREFIX = "Fix: boto ref"

    attr_reader :violations

    def initialize(violations)
      @violations = violations.dup.freeze
      super(build_message(violations))
    end

    private

    def build_message(violations)
      violations.group_by(&:project).map { |project, items| project_block(project, items) }.join("\n")
    end

    def project_block(project, items)
      header = %(project "#{project}" uses projects it does not reference:)
      lines = [header, *items.map { violation_line(_1) }, *fix_lines(project, items)]
      lines.join("\n")
    end

    def violation_line(violation)
      "  #{violation.path}:#{violation.line}  #{violation.constant}  (#{violation.missing_ref} is not in refs)"
    end

    def fix_lines(project, items)
      items.map(&:missing_ref).uniq.map { "#{FIX_PREFIX} #{project} #{_1}" }
    end
  end
end
