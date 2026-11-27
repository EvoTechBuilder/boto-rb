# frozen_string_literal: true

require_relative "lib/boto/database/version"

Gem::Specification.new do |spec|
  spec.name = "boto-rb-data"
  spec.version = Boto::Database::VERSION
  spec.authors = ["Evo Tech Builder"]
  spec.license = "MIT"
  spec.summary = "Repositories, the :database plugin and migrations for Boto, on Sequel."
  spec.homepage = "https://github.com/EvoTechBuilder/boto-rb"
  spec.required_ruby_version = ">= 3.4"
  spec.metadata["rubygems_mfa_required"] = "true"
  spec.metadata["source_code_uri"] = spec.homepage
  spec.metadata["changelog_uri"] = "#{spec.homepage}/blob/main/CHANGELOG.md"

  spec.files = Dir["lib/**/*.rb"] + ["LICENSE"]
  spec.require_paths = ["lib"]

  spec.add_dependency "boto-rb", "= #{Boto::Database::VERSION}"
  spec.add_dependency "sequel", "~> 5.0"
  spec.add_development_dependency "sqlite3", "~> 2.0"
end
