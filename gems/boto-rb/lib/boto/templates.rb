# frozen_string_literal: true

module Boto
  # Registry of project templates. Loaded lazily once per process, then frozen.
  module Templates
    class Error < StandardError; end
    class DuplicateTemplateError < Error; end
    class ClosedRegistryError < Error; end
    class UnknownTemplateError < KeyError; end

    GEM_PATTERN = "boto/templates/*/template.rb"
    # Loading runs declarations that call back into the registry, so the lock must not be taken there.
    LOCK = Mutex.new

    class << self
      def fetch(name)
        registry.fetch(normalize(name)) { raise UnknownTemplateError, unknown_message(name) }
      end

      def key?(name) = registry.key?(normalize(name))

      def http?(name) = fetch(name).http

      def all = registry.values.sort_by(&:name)

      def unknown_message(name)
        "unknown template #{name.inspect} (available: #{all.map(&:name).join(", ")}; is its gem in the Gemfile?)"
      end

      # Internal: called by Template.define while the registry loads.
      def add(template)
        raise ClosedRegistryError, "templates can only be declared in a template.rb file" unless @collecting

        existing = @collecting[template.name]
        raise DuplicateTemplateError, duplicate_message(existing, template) if existing

        @collecting[template.name] = template
      end

      # For tests: forgets the registry so the next lookup loads it again.
      def reset!
        LOCK.synchronize { @registry = nil }
      end

      private

      def registry
        @registry || LOCK.synchronize { @registry || load_registry }
      end

      def load_registry
        @collecting = {}
        # load, not require: a reset! must run the declarations again.
        (official_files + gem_files).each { |path| load(path) }
        @registry = @collecting.freeze
      ensure
        @collecting = nil
      end

      def official_files = Dir[File.join(Template::OFFICIAL_DIR, "*", "template.rb")].sort

      # realpath + uniq: the same file can be on $LOAD_PATH twice; official files are already loaded above.
      def gem_files
        Gem.find_files(GEM_PATTERN)
           .map { |path| File.realpath(path) }
           .uniq
           .reject { |path| Template.official_path?(path) }
           .sort
      end

      def normalize(name) = name.is_a?(String) ? name.to_sym : name

      def duplicate_message(existing, template)
        if existing.source == Template::OFFICIAL_SOURCE
          "template :#{template.name} is official and cannot be redefined by #{template.source}"
        else
          "template :#{template.name} is defined twice, by #{existing.source} and #{template.source}"
        end
      end
    end
  end
end
