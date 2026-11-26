# frozen_string_literal: true

require "set"

module Boto
  # Checks that each project only uses the namespaces of projects it references directly.
  module Isolation
    Violation = Data.define(:project, :path, :line, :constant, :missing_ref)
    NamespaceViolation = Data.define(:project, :path, :line, :constant, :namespace)

    SOURCE_DIRS = %w[endpoints operations models schemas config test].freeze
    RUBY_GLOB = "**/*.rb"
    TEST_DIR = "test"
    SORT_KEYS = ->(violation) { [violation.project, violation.path, violation.line] }

    def self.check(solution, root:, projects: nil)
      owners = namespace_owners(solution)
      selected = projects ? projects.map { solution.project(_1) } : solution.projects
      selected.flat_map { |project| project_violations(project, owners, root) }.sort_by(&SORT_KEYS)
    end

    def self.namespace_owners(solution)
      solution.projects.to_h { [_1.namespace_name, _1.name] }
    end

    def self.project_violations(project, owners, root)
      scans = scan_project(project, root)
      reference_violations(project, owners, scans) + namespace_violations(project, scans)
    end

    def self.reference_violations(project, owners, scans)
      declared = scans.flat_map { |_path, scan| scan.declared.to_a }.to_set
      allowed = [project.name, *project.refs].to_set

      scans.flat_map do |path, scan|
        scan.used.filter_map do |use|
          owner = owners[use.root]
          next if owner.nil? || allowed.include?(owner) || declared.include?(use.root)

          Violation.new(project: project.name, path: path, line: use.line, constant: use.constant, missing_ref: owner)
        end
      end
    end

    # Test files run in their own process, so their top-level constants never reach the shared Object.
    def self.namespace_violations(project, scans)
      scans.flat_map do |path, scan|
        next [] if test_file?(project, path)

        scan.top_level.filter_map do |declaration|
          next if declaration.root == project.namespace_name

          NamespaceViolation.new(project: project.name, path: path, line: declaration.line,
                                 constant: declaration.constant, namespace: project.namespace_name)
        end
      end
    end

    def self.test_file?(project, path)
      path.start_with?(File.join(project.path, TEST_DIR, ""))
    end

    # Paths are relative to the solution root, sorted, and only for directories that exist.
    def self.scan_project(project, root)
      source_paths(project, root).map do |path|
        [path, Scanner.scan(File.read(File.join(root, path)), path: path)]
      end
    end

    def self.source_paths(project, root)
      SOURCE_DIRS.flat_map do |dir|
        Dir.glob(RUBY_GLOB, base: File.join(root, project.path, dir)).map { File.join(project.path, dir, _1) }
      end.sort
    end

    private_class_method :namespace_owners, :project_violations, :reference_violations, :namespace_violations,
                         :test_file?, :scan_project, :source_paths
  end
end
