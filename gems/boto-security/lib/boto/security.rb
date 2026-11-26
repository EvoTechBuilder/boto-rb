# frozen_string_literal: true

require "boto"
require "zeitwerk"

loader = Zeitwerk::Loader.for_gem_extension(Boto)
loader.setup

module Boto
  # Security plugins (hosts, cors, auth, rate_limit) that a project enables with app.use.
  module Security
  end
end
