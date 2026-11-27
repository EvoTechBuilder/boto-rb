# frozen_string_literal: true

require "boto"
require "zeitwerk"

loader = Zeitwerk::Loader.for_gem_extension(Boto)
loader.setup

module Boto
  # Repositories, the :database plugin and migrations, on Sequel. Named Database, not Data, because
  # Data.define is used inside Boto by the core and by third-party plugins.
  module Database
  end
end
