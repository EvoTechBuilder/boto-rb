# frozen_string_literal: true

require "boto"
require "sequel"
require "zeitwerk"

# Times are stored and read in UTC, so a created_at written by one server reads back the same on any other.
Sequel.default_timezone = :utc

loader = Zeitwerk::Loader.for_gem_extension(Boto)
loader.setup

module Boto
  # Repositories, the :database plugin and migrations, on Sequel. Named Database, not Data, because
  # Data.define is used inside Boto by the core and by third-party plugins.
  module Database
  end
end
