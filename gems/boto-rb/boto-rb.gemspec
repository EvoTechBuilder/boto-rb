# frozen_string_literal: true

require_relative "lib/boto/version"

Gem::Specification.new do |spec|
  spec.name = "boto-rb"
  spec.version = Boto::VERSION
  spec.authors = ["Evo Tech Builder"]
  spec.license = "MIT"
  spec.summary = "Ruby framework for APIs and microservices organized as solutions."
  spec.required_ruby_version = ">= 3.4"
  spec.metadata["rubygems_mfa_required"] = "true"

  spec.files = Dir["lib/**/*.rb"]
  spec.require_paths = ["lib"]

  spec.add_dependency "rack", "~> 3.1"
  spec.add_dependency "zeitwerk", "~> 2.7"
end
