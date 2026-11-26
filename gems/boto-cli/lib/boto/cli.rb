# frozen_string_literal: true

require "boto"
require "zeitwerk"

loader = Zeitwerk::Loader.for_gem_extension(Boto)
loader.inflector.inflect("cli" => "CLI")
# support/ groups helpers on disk without adding a namespace (Boto::CLI::Generator stays the same).
loader.collapse("#{__dir__}/cli/support")
loader.setup

module Boto
  module CLI
  end
end
