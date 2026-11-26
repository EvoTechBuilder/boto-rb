# frozen_string_literal: true

require_relative "lib/boto/security/version"

Gem::Specification.new do |spec|
  spec.name = "boto-rb-security"
  spec.version = Boto::Security::VERSION
  spec.authors = ["Evo Tech Builder"]
  spec.license = "MIT"
  spec.summary = "Security plugins for the Boto framework: auth, CORS, hosts and rate limiting."
  spec.homepage = "https://github.com/EvoTechBuilder/boto-rb"
  spec.required_ruby_version = ">= 3.4"
  spec.metadata["rubygems_mfa_required"] = "true"
  spec.metadata["source_code_uri"] = spec.homepage
  spec.metadata["changelog_uri"] = "#{spec.homepage}/blob/main/CHANGELOG.md"

  spec.files = Dir["lib/**/*.rb"] + ["LICENSE"]
  spec.require_paths = ["lib"]

  spec.add_dependency "boto-rb", "= #{Boto::Security::VERSION}"
  spec.add_dependency "jwt", "~> 3.0"
end
