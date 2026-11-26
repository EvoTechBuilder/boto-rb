# frozen_string_literal: true

require "boto"
require "zeitwerk"

loader = Zeitwerk::Loader.for_gem_extension(Boto)
loader.inflector.inflect("cli" => "CLI")
loader.setup

module Boto
  module CLI
  end
end
