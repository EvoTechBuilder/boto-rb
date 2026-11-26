# frozen_string_literal: true

module Boto
  module CLI
    module Commands
      class New < Command
        SUMMARY = "Create a new solution"
        TEMPLATE = "solution"
        USAGE = "usage: boto new <name>"

        def call
          name = name_argument
          ensure_available!(name)
          files = Generator.new(TEMPLATE).generate(
            File.join(cwd, name),
            name: name, ruby_version: RUBY_VERSION, boto_version: Boto::CLI::VERSION
          )
          files.each { |file| out.puts "create #{name}/#{file}" }
          out.puts "Next: cd #{name} && boto add webapi api"
          SUCCESS
        end

        private

        def name_argument
          name = argv.first
          raise Error, USAGE if name.nil?
          raise Error, %(invalid solution name "#{name}") unless Boto::Botofile::NAME_FORMAT.match?(name)

          name
        end

        def ensure_available!(name)
          raise Error, %(directory "#{name}" already exists) if File.exist?(File.join(cwd, name))
        end
      end
    end
  end
end
