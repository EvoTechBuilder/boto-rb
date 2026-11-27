# frozen_string_literal: true

module Boto
  module CLI
    # Answers what is already in a project folder, so the generator can refuse before it writes anything.
    class ProjectFolder
      SCHEMAS_FOLDER = "schemas"
      # Zeitwerk loads the same relative path in any of these folders as one constant.
      CODE_FOLDERS = %w[endpoints operations models schemas].freeze
      CONFIG_FILE = File.join("config", "app.rb")
      AUTH_PLUGIN = /^\s*app\.use\s+:auth\b/

      def initialize(dir)
        @dir = dir
      end

      def schema?(reference) = File.file?(File.join(@dir, SCHEMAS_FOLDER, "#{reference}.rb"))

      def auth_enabled?
        path = File.join(@dir, CONFIG_FILE)
        File.file?(path) && AUTH_PLUGIN.match?(File.read(path))
      end

      # The path, under the project, of a file in another code folder that would define the same constant.
      def clashing_path(file)
        folder, relative = file.path.split(File::SEPARATOR, 2)
        return unless CODE_FOLDERS.include?(folder)

        (CODE_FOLDERS - [folder]).map { File.join(_1, relative) }.find { File.exist?(File.join(@dir, _1)) }
      end
    end
  end
end
