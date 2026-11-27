# frozen_string_literal: true

require_relative "lib/boto/gateway/version"

Gem::Specification.new do |spec|
  spec.name = "boto-rb-gateway"
  spec.version = Boto::Gateway::VERSION
  spec.authors = ["Evo Tech Builder"]
  spec.license = "MIT"
  spec.summary = "Single entry point for a Boto solution in development, with the /_boto panel."
  spec.homepage = "https://github.com/EvoTechBuilder/boto-rb"
  spec.required_ruby_version = ">= 3.4"
  spec.metadata["rubygems_mfa_required"] = "true"
  spec.metadata["source_code_uri"] = spec.homepage
  spec.metadata["changelog_uri"] = "#{spec.homepage}/blob/main/CHANGELOG.md"

  spec.files = Dir["lib/**/*"].select { |path| File.file?(path) } + ["LICENSE", "README.md"]
  spec.require_paths = ["lib"]

  spec.add_dependency "boto-rb", "= #{Boto::Gateway::VERSION}"
end
