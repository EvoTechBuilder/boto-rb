# frozen_string_literal: true

module Boto
  # Loads a solution's projects in dependency order and builds the Rack app of one project.
  class Boot
    def initialize(solution, root:)
      @solution = solution
      @root = root
      @loaders = {}
    end

    def load(name)
      loaders = load_order(name).map { |item| loader_for(item) }
      loaders.each(&:setup)
      loaders.each(&:eager_load)
      loader_for(name).namespace
    end

    def app(name, **app_options)
      App.new(namespace: load(name), **app_options)
    end

    def shutdown
      @loaders.each_value(&:unload)
      @loaders.clear
    end

    private

    def load_order(name)
      @solution.dependencies_of(name) + [name]
    end

    def loader_for(name)
      @loaders[name] ||= ProjectLoader.new(@solution.project(name), root: @root)
    end
  end
end
