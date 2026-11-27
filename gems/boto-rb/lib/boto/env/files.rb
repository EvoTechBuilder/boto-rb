# frozen_string_literal: true

module Boto
  class Env
    # Finds the .env files of one directory in precedence order (highest first).
    module Files
      BASE_FILE = ".env"
      LOCAL_FILE = ".env.local"
      TEST_ENV = "test"

      def self.for(dir, env_name:)
        names_for(env_name).map { File.expand_path(_1, dir) }.select { File.file?(_1) }
      end

      # Merges the files so the highest precedence one wins each key.
      def self.read(dir, env_name:)
        self.for(dir, env_name:).reverse.each_with_object({}) do |path, merged|
          merged.merge!(Parser.parse(File.read(path), path:))
        end.freeze
      end

      # .env.local stays out of tests so the suite does not depend on the developer's machine.
      def self.names_for(env_name)
        names = [".env.#{env_name}.local", LOCAL_FILE, ".env.#{env_name}", BASE_FILE]
        env_name == TEST_ENV ? names - [LOCAL_FILE] : names
      end

      private_class_method :names_for
    end
  end
end
