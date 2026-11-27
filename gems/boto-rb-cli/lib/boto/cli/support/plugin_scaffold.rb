# frozen_string_literal: true

module Boto
  module CLI
    # Decides which parts of templates/plugin make up an extension gem, and the values they render with.
    class PluginScaffold
      PARTS_DIR = "plugin"
      BASE_PART = "base"
      PLUGIN_PART = "plugin"
      SHIM_PART = "shim"
      TEMPLATE_PART = "template"
      DEFAULT_FOLDER = "apps"

      def initialize(name, options, year:)
        @name = name
        @options = options
        @year = year
      end

      def directories
        parts.map { |part| Generator.official_dir(File.join(PARTS_DIR, part)) }
      end

      def locals
        {
          gem_name: @name.gem_name, extension: @name.extension, module_name: @name.module_name,
          plugin: plugin, plugin_class: class_name(plugin), shim_plugin: shim_plugin,
          template: template, template_class: class_name(template),
          folder: @options.fetch(:folder, DEFAULT_FOLDER), http: @options.fetch(:http, false),
          boto_requirement: boto_requirement, year: @year
        }
      end

      private

      def parts
        parts = [BASE_PART]
        parts << PLUGIN_PART if plugin
        parts << SHIM_PART if shim_plugin
        parts << TEMPLATE_PART if template
        parts
      end

      def plugin = @options[:plugin]

      def template = @options[:template]

      # The core requires boto/<plugin> to find a plugin, so a plugin named differently from the gem needs a shim.
      def shim_plugin
        return if plugin.nil? || plugin == @name.extension

        plugin
      end

      def class_name(value) = value && ExtensionName.camelize(value)

      # Same major.minor as the CLI, which ships with the boto-rb of the same version.
      def boto_requirement
        major, minor, = Boto::CLI::VERSION.split(".")
        "~> #{major}.#{minor}.0"
      end
    end
  end
end
