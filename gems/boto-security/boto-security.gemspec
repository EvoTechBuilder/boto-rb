# frozen_string_literal: true

require_relative "lib/boto/security/version"

Gem::Specification.new do |spec|
  spec.name = "boto-security"
  spec.version = Boto::Security::VERSION
  spec.authors = ["Evo Tech Builder"]
  spec.license = "MIT"
  spec.summary = "Security plugins for the Boto framework: auth, CORS, hosts and rate limiting."
  spec.required_ruby_version = ">= 3.4"
  spec.metadata["rubygems_mfa_required"] = "true"

  spec.files = Dir["lib/**/*.rb"]
  spec.require_paths = ["lib"]

  spec.add_dependency "boto-rb", "= #{Boto::Security::VERSION}"
  spec.add_dependency "jwt", "~> 3.0"
end
