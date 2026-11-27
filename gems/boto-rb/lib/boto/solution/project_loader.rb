# frozen_string_literal: true

require "zeitwerk"

module Boto
  # Loads one project's code directories directly under its namespace, using a Zeitwerk
  # loader of its own so each project can be set up and unloaded independently.
  class ProjectLoader
    CODE_DIRS = %w[endpoints operations models schemas].freeze

    attr_reader :namespace

    def initialize(project, root:)
      @project = project
      @root = root
      @namespace = resolve_namespace(project.namespace_name)
      @loader = Zeitwerk::Loader.new
      @loader.tag = project.name
      # Without it Zeitwerk does not track what it loads, so unload would leave the constants and files behind
      # (a failed boot would leak them, and the dev reload would keep serving the old code).
      @loader.enable_reloading
      @set_up = false
    end

    def setup
      return self if @set_up

      code_dirs.each { |dir| @loader.push_dir(dir, namespace: namespace) }
      @loader.setup
      @set_up = true
      self
    end

    def eager_load
      setup
      @loader.eager_load
      self
    end

    def unload
      @loader.unload
    ensure
      @loader.unregister
    end

    private

    def resolve_namespace(name)
      return Object.const_get(name, false) if Object.const_defined?(name, false)

      Object.const_set(name, Module.new)
    end

    def code_dirs
      base = File.join(@root, @project.path)
      CODE_DIRS.map { |dir| File.join(base, dir) }.select { |dir| File.directory?(dir) }
    end
  end
end
