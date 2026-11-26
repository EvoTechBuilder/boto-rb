# frozen_string_literal: true

require_relative "lib/boto/cli/version"

Gem::Specification.new do |spec|
  spec.name = "boto-cli"
  spec.version = Boto::CLI::VERSION
  spec.authors = ["Evo Tech Builder"]
  spec.license = "MIT"
  spec.summary = "Command line interface for the Boto framework."
  spec.required_ruby_version = ">= 3.4"
  spec.metadata["rubygems_mfa_required"] = "true"

  spec.files = Dir["lib/**/*.rb"] + Dir["exe/*"] + Dir["templates/**/*", "templates/**/.*"]
  spec.bindir = "exe"
  spec.executables = ["boto"]
  spec.require_paths = ["lib"]

  spec.add_dependency "boto", "= #{Boto::CLI::VERSION}"
  spec.add_dependency "falcon", "~> 0.47"
end
