# frozen_string_literal: true

require "optparse"

module Boto
  module CLI
    module Commands
      # Generates a gem that extends Boto: the base gem, plus a plugin and/or a template. Named Plugin here, so the
      # core's Boto::Plugin is always written with the leading ::.
      class Plugin < Command
        SUMMARY = "Create a gem that extends Boto (plugin, template or both)"
        USAGE = "Usage: boto plugin new <gem> [--plugin NAME] [--template NAME] [--http] [--folder FOLDER] [--name NAME]"
        POSITION = 12
        NEW = "new"
        RESERVED_PLUGINS = %w[health openapi swagger_ui database auth cors hosts rate_limit secure_headers sessions
                              csrf].freeze
        OPTIONS = [
          Option.new(key: :plugin, flags: %w[--plugin], argument: "NAME",
                     description: "Plugin to generate, used as app.use :NAME"),
          Option.new(key: :template, flags: %w[--template], argument: "NAME",
                     description: "Template to generate, used as boto add NAME"),
          Option.new(key: :http, flags: %w[--http], description: "The template is an HTTP project (needs --template)"),
          Option.new(key: :folder, flags: %w[--folder], argument: "FOLDER",
                     description: "Folder of the template: apps, libs or workers (needs --template)"),
          Option.new(key: :name, flags: %w[--name], argument: "NAME",
                     description: "Extension name, instead of the one derived from the gem name")
        ].freeze

        def initialize(argv, out:, err:, cwd:, year: Time.now.year)
          super(argv, out: out, err: err, cwd: cwd)
          @year = year
        end

        def call
          subcommand, *rest = argv
          raise Error, USAGE unless subcommand == NEW

          options = {}
          gem_name = parse_arguments(rest, options)
          check_options!(options)
          scaffold = PluginScaffold.new(ExtensionName.new(gem_name, override: options[:name]), options, year: @year)
          ensure_available!(gem_name)
          warn_reserved!(options)
          files = write_files(File.join(cwd, gem_name), scaffold)
          files.each { |file| out.puts "create #{gem_name}/#{file}" }
          out.puts "Next: cd #{gem_name} && bundle install && bundle exec rake test"
          SUCCESS
        end

        private

        def parse_arguments(rest, options)
          gem_name, *extra = option_parser(options).parse(rest)
          raise Error, USAGE if gem_name.nil? || !extra.empty?

          gem_name
        rescue OptionParser::ParseError => error
          raise Error, error.message
        end

        def check_options!(options)
          check_template_options!(options)
          ExtensionName.check_name!("plugin", options[:plugin]) if options.key?(:plugin)
          ExtensionName.check_name!("template", options[:template]) if options.key?(:template)
          check_folder!(options[:folder]) if options.key?(:folder)
        end

        def check_template_options!(options)
          return if options.key?(:template) || (options.keys & %i[http folder]).empty?

          raise Error, "--http and --folder only apply with --template"
        end

        def check_folder!(folder)
          folders = ::Boto::Template::Builder::FOLDERS
          return if folders.include?(folder)

          raise Error, %(folder must be one of #{folders.join(", ")}, got "#{folder}")
        end

        def ensure_available!(gem_name)
          raise Error, %(directory "#{gem_name}" already exists) if File.exist?(File.join(cwd, gem_name))
        end

        def warn_reserved!(options)
          warn_reserved_name("plugin", options[:plugin], RESERVED_PLUGINS) if options.key?(:plugin)
          warn_reserved_name("template", options[:template], official_templates) if options.key?(:template)
        end

        def warn_reserved_name(kind, name, reserved)
          return unless reserved.include?(name)

          err.puts %(warning: #{kind} name "#{name}" is reserved by Boto (built-in or official), the gem may clash)
        end

        def official_templates
          ::Boto::Templates.all
                           .select { |template| template.source == ::Boto::Template::OFFICIAL_SOURCE }
                           .map { |template| template.name.to_s }
        end

        def write_files(target, scaffold)
          locals = scaffold.locals
          scaffold.directories
                  .flat_map { |directory| Generator.new(directory).generate(target, locals) }
                  .sort
        end
      end
    end
  end
end
