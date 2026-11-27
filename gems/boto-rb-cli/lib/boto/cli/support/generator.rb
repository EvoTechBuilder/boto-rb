# frozen_string_literal: true

require "erb"
require "fileutils"

module Boto
  module CLI
    # Copies a template folder into a project, rendering the .erb files with the given locals.
    class Generator
      TEMPLATES_ROOT = File.expand_path("../../../../templates", __dir__)
      ERB_EXTENSION = ".erb"
      ERB_TRIM_MODE = "-"

      def self.official_dir(name) = File.join(TEMPLATES_ROOT, name.to_s)

      # A template from a gem ships its files; an official one without files uses the copy in this gem.
      def self.source_for(template) = template.files || official_dir(template.name)

      def self.available?(template) = File.directory?(source_for(template))

      def self.for_template(template) = new(source_for(template))

      def self.inside?(path, folder)
        File.expand_path(path).start_with?(File.join(File.expand_path(folder), ""))
      end

      def initialize(dir)
        raise Error, %(missing template folder "#{dir}") unless File.directory?(dir)

        @dir = dir
      end

      def generate(target_dir, locals)
        template_files.map { |relative| materialize(relative, target_dir, locals) }.sort
      end

      private

      def template_files
        Dir.glob("**/*", File::FNM_DOTMATCH, base: @dir)
           .reject { |relative| File.directory?(File.join(@dir, relative)) }
      end

      def materialize(relative, target_dir, locals)
        output = relative.delete_suffix(ERB_EXTENSION)
        target = File.join(target_dir, output)
        ensure_inside!(target, target_dir, output)
        FileUtils.mkdir_p(File.dirname(target))
        source = File.join(@dir, relative)
        if relative.end_with?(ERB_EXTENSION)
          File.write(target, render(File.read(source), locals))
        else
          FileUtils.cp(source, target)
        end
        output
      end

      # Defensive: a relative path with ".." would write outside the project folder.
      def ensure_inside!(target, target_dir, output)
        return if self.class.inside?(target, target_dir)

        raise Error, %(output path "#{output}" escapes the project folder)
      end

      def render(content, locals)
        ERB.new(content, trim_mode: ERB_TRIM_MODE).result_with_hash(locals)
      end
    end
  end
end
