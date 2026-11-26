# frozen_string_literal: true

module Boto
  class Solution
    class CycleError < StandardError
      SEPARATOR = " -> "

      attr_reader :path

      def initialize(path)
        @path = path.freeze
        super("cycle detected: #{path.join(SEPARATOR)}")
      end
    end

    VISITING = :visiting
    VISITED = :visited

    attr_reader :name, :projects

    def initialize(name:, projects:)
      @name = name.dup.freeze
      @projects = projects.dup.freeze
      @index = projects.to_h { |item| [item.name, item] }.freeze
      freeze
    end

    def project(name)
      @index.fetch(name) { raise KeyError, "unknown project \"#{name}\"" }
    end

    def topological_order
      state = {}
      order = []
      @projects.each { |item| visit(item.name, state, [], order) }
      order.map { |item_name| project(item_name) }
    end

    def dependencies_of(name)
      reachable = reachable_names(project(name).refs)
      topological_order.map(&:name).select { |item_name| reachable.include?(item_name) }
    end

    def dependents_of(name)
      project(name)
      @projects.map(&:name).select do |item_name|
        item_name != name && dependencies_of(item_name).include?(name)
      end
    end

    private

    def visit(name, state, stack, order)
      case state[name]
      when VISITED then return
      when VISITING then raise CycleError, cycle_from(stack, name)
      end

      state[name] = VISITING
      stack.push(name)
      project(name).refs.each { |ref| visit(ref, state, stack, order) }
      stack.pop
      state[name] = VISITED
      order << name
    end

    def cycle_from(stack, name)
      stack.drop(stack.index(name)) + [name]
    end

    def reachable_names(refs)
      pending = refs.dup
      reached = []
      until pending.empty?
        ref = pending.shift
        next if reached.include?(ref)

        reached << ref
        pending.concat(project(ref).refs)
      end
      reached
    end
  end
end
