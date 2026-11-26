# frozen_string_literal: true

module Boto
  module CLI
    module Commands
      class Ref < Command
        SUMMARY = "Add a reference between projects"
        USAGE = "Usage: boto ref <project> <reference>"
        POSITION = 3

        def call
          project, ref = argv
          raise Error, USAGE if project.nil? || ref.nil?
          # Guards the %w[] insertion: a name with spaces would become several refs.
          raise Error, %(invalid reference "#{ref}") unless Boto::Botofile::NAME_FORMAT.match?(ref)

          add_reference(botofile_path, project, ref)
          out.puts "#{project} -> #{ref}"
          SUCCESS
        end

        private

        def botofile_path
          path = File.join(cwd, BOTOFILE_NAME)
          raise Error, "Botofile not found in #{cwd}" unless File.file?(path)

          path
        end

        # Validates the edited source before writing, so an invalid reference never reaches the file.
        def add_reference(path, project, ref)
          source = BotofileEditor.add_ref(File.read(path), project: project, ref: ref)
          Boto::Botofile.parse(source, path: path)
          File.write(path, source)
        end
      end
    end
  end
end
