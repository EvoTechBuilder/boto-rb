# frozen_string_literal: true

require_relative "lib/boto/swagger_ui/version"

Gem::Specification.new do |spec|
  spec.name = "boto-rb-swaggerui"
  spec.version = Boto::SwaggerUi::VERSION
  spec.authors = ["Evo Tech Builder"]
  # The gem is MIT; the vendored Swagger UI (vendor/swagger-ui) keeps its Apache-2.0 license.
  spec.licenses = ["MIT", "Apache-2.0"]
  spec.summary = "Swagger UI for Boto apps, served by the :swagger_ui plugin."
  spec.homepage = "https://github.com/EvoTechBuilder/boto-rb"
  spec.required_ruby_version = ">= 3.4"
  spec.metadata["rubygems_mfa_required"] = "true"
  spec.metadata["source_code_uri"] = spec.homepage
  spec.metadata["changelog_uri"] = "#{spec.homepage}/blob/main/CHANGELOG.md"

  spec.files = Dir["lib/**/*.rb"] + Dir["vendor/**/*"] + ["LICENSE"]
  spec.require_paths = ["lib"]

  spec.add_dependency "boto-rb", "= #{Boto::SwaggerUi::VERSION}"
end
