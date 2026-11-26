# frozen_string_literal: true

require "boto/security"
require "redis-client"
require "zeitwerk"

loader = Zeitwerk::Loader.for_gem_extension(Boto)
loader.setup

module Boto
  # Redis-backed stores for Boto plugins.
  module Redis
  end
end
