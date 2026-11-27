# frozen_string_literal: true

require "boto"
require "zeitwerk"

loader = Zeitwerk::Loader.for_gem_extension(Boto)
loader.setup

module Boto
  # Swagger UI static assets and the HTML page that loads them.
  module SwaggerUi
  end
end
