# frozen_string_literal: true

module Boto
  module CLI
    class Command
      SUCCESS = 0
      FAILURE = 1
      BOTOFILE_NAME = "Botofile"

      attr_reader :argv, :out, :err, :cwd

      def initialize(argv, out:, err:, cwd:)
        @argv = argv
        @out = out
        @err = err
        @cwd = cwd
      end

      def call
        raise NotImplementedError, "#{self.class} must implement #call"
      end

      private

      def solution
        path = File.join(cwd, BOTOFILE_NAME)
        raise Error, "Botofile not found in #{cwd}" unless File.file?(path)

        Botofile.load(path)
      end
    end
  end
end
