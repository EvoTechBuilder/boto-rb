# frozen_string_literal: true

require "boto"
require "zeitwerk"

loader = Zeitwerk::Loader.for_gem_extension(Boto)
# Template declarations run through Boto::Template.define when the registry loads; they are not constants.
loader.ignore("#{__dir__}/templates")
loader.setup

module Boto
  # Namespace of the gem; its plugins and templates are loaded from lib/boto/.
  module Gateway
  end
end
