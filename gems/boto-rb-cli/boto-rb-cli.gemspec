# frozen_string_literal: true

require_relative "lib/boto/cli/version"

Gem::Specification.new do |spec|
  spec.name = "boto-rb-cli"
  spec.version = Boto::CLI::VERSION
  spec.authors = ["Evo Tech Builder"]
  spec.license = "MIT"
  spec.summary = "Command line interface for the Boto framework."
  spec.homepage = "https://github.com/EvoTechBuilder/boto-rb"
  spec.required_ruby_version = ">= 3.4"
  spec.metadata["rubygems_mfa_required"] = "true"
  spec.metadata["source_code_uri"] = spec.homepage
  spec.metadata["changelog_uri"] = "#{spec.homepage}/blob/main/CHANGELOG.md"

  spec.files = Dir["lib/**/*.rb"] + ["LICENSE"] + Dir["exe/*"] + Dir.glob("templates/**/*", File::FNM_DOTMATCH).select { |path| File.file?(path) }
  spec.bindir = "exe"
  spec.executables = ["boto"]
  spec.require_paths = ["lib"]

  spec.add_dependency "boto-rb", "= #{Boto::CLI::VERSION}"
  spec.add_dependency "falcon", "~> 0.57"
end
