# frozen_string_literal: true

require "erb"
require "fileutils"

module Boto
  module CLI
    class Generator
      TEMPLATES_ROOT = File.expand_path("../../../templates", __dir__)
      ERB_EXTENSION = ".erb"
      ERB_TRIM_MODE = "-"

      def initialize(template_name)
        @dir = File.join(TEMPLATES_ROOT, template_name)
        raise Error, %(unknown template "#{template_name}") unless File.directory?(@dir)
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
        FileUtils.mkdir_p(File.dirname(target))
        source = File.join(@dir, relative)
        if relative.end_with?(ERB_EXTENSION)
          File.write(target, render(File.read(source), locals))
        else
          FileUtils.cp(source, target)
        end
        output
      end

      def render(content, locals)
        ERB.new(content, trim_mode: ERB_TRIM_MODE).result_with_hash(locals)
      end
    end
  end
end
