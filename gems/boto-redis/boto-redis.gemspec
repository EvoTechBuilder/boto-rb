# frozen_string_literal: true

require_relative "lib/boto/redis/version"

Gem::Specification.new do |spec|
  spec.name = "boto-redis"
  spec.version = Boto::Redis::VERSION
  spec.authors = ["Evo Tech Builder"]
  spec.license = "MIT"
  spec.summary = "Redis-backed stores for Boto plugins (rate limiting today, sessions and cache later)."
  spec.required_ruby_version = ">= 3.4"
  spec.metadata["rubygems_mfa_required"] = "true"

  spec.files = Dir["lib/**/*.rb"]
  spec.require_paths = ["lib"]

  spec.add_dependency "boto-security", "= #{Boto::Redis::VERSION}"
  spec.add_dependency "connection_pool", "~> 3.0"
  spec.add_dependency "redis-client", "~> 0.31"
end
