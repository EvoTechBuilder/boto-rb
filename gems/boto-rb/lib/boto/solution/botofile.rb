# frozen_string_literal: true

module Boto
  class Botofile
    class InvalidError < StandardError; end

    NAME_FORMAT = /\A[a-z][a-z0-9_]*\z/
    DEFAULT_PATH = "Botofile"
    FIRST_LINE = 1

    def self.load(path)
      parse(File.read(path), path: path)
    end

    def self.parse(source, path: DEFAULT_PATH)
      dsl = DSL.new(path)
      dsl.instance_eval(source, path, FIRST_LINE)
      dsl.to_solution
    end

    # BasicObject keeps the Botofile's visible surface down to `solution` and `project`.
    class DSL < BasicObject
      def initialize(path)
        @path = path
        @solution_name = nil
        @projects = []
      end

      def solution(name)
        line = ::Kernel.caller_locations(1, 1).first.lineno
        invalid!("solution declared twice", line) if @solution_name
        name = frozen_string(name)
        invalid!(%(invalid solution name "#{name}"), line) unless ::Boto::Botofile::NAME_FORMAT.match?(name)
        @solution_name = name
        nil
      end

      def project(name, template:, refs: [])
        line = ::Kernel.caller_locations(1, 1).first.lineno
        name = frozen_string(name)
        refs = normalize_refs(refs)
        check_project(name, template, refs, line)
        @projects << ::Boto::Project.new(name: name, template: template, refs: refs, line: line)
        nil
      end

      def to_solution
        invalid!("solution name is missing") unless @solution_name
        check_references
        solution = ::Boto::Solution.new(name: @solution_name, projects: @projects)
        solution.topological_order
        solution
      rescue ::Boto::Solution::CycleError => error
        invalid!(error.message)
      end

      private

      def invalid!(message, line = nil)
        location = line ? "#{@path}:#{line}" : @path
        ::Kernel.raise ::Boto::Botofile::InvalidError, "#{location}: #{message}"
      end

      def frozen_string(value)
        value.to_s.dup.freeze
      end

      def normalize_refs(refs)
        ::Kernel.Array(refs).map { |ref| frozen_string(ref) }.freeze
      end

      def check_project(name, template, refs, line)
        invalid!(%(invalid project name "#{name}"), line) unless ::Boto::Botofile::NAME_FORMAT.match?(name)
        invalid!("unknown template #{template.inspect}", line) unless ::Boto::Project::TEMPLATE_DIRS.key?(template)
        invalid!(%(duplicate project "#{name}"), line) if declared?(name)
        invalid!(%(project "#{name}" references itself), line) if refs.include?(name)
        duplicate = refs.find { |ref| refs.count(ref) > 1 }
        invalid!(%(duplicate reference "#{duplicate}"), line) if duplicate
        check_namespace(name, line)
      end

      def declared?(name)
        @projects.any? { |project| project.name == name }
      end

      # Different names can map to the same Ruby namespace (foo_bar and foo__bar both give FooBar).
      def check_namespace(name, line)
        namespace = ::Boto::Project.namespace_for(name)
        owner = @projects.find { |project| project.namespace_name == namespace }
        return unless owner

        invalid!(%(project "#{name}" has the same namespace #{namespace} as project "#{owner.name}"), line)
      end

      def check_references
        names = @projects.map(&:name)
        @projects.each do |project|
          unknown = project.refs.find { |ref| !names.include?(ref) }
          invalid!(%(unknown reference "#{unknown}"), project.line) if unknown
        end
      end
    end
    private_constant :DSL
  end
end
