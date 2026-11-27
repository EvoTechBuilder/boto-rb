# frozen_string_literal: true

require "fileutils"

module Boto
  module CLI
    # A file to write, with its path relative to the project folder.
    class GeneratedFile < Data.define(:path, :content)
      # Every write stays inside the project folder, even if a name ever slips past ConstantName.
      def target(dir)
        root = File.expand_path(dir)
        absolute = File.expand_path(path, root)
        return absolute if absolute.start_with?("#{root}#{File::SEPARATOR}")

        raise Error, %(path "#{path}" leaves the project folder)
      end

      def exist?(dir) = File.exist?(target(dir))

      def write(dir)
        absolute = target(dir)
        FileUtils.mkdir_p(File.dirname(absolute))
        File.write(absolute, content)
      end
    end
  end
end
