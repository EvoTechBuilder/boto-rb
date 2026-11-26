# frozen_string_literal: true

require "zeitwerk"
loader = Zeitwerk::Loader.for_gem
loader.inflector.inflect("openapi" => "OpenAPI")
loader.setup

module Boto
end
