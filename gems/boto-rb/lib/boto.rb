# frozen_string_literal: true

require "zeitwerk"

module Boto
  # Names Zeitwerk cannot camelize from the file name alone (lib/boto/plugins/openapi.rb -> OpenAPI).
  INFLECTIONS = { "openapi" => "OpenAPI" }.freeze
end

loader = Zeitwerk::Loader.for_gem
loader.inflector.inflect(Boto::INFLECTIONS)
# Area folders group files on disk without adding a namespace (Boto::Router stays Boto::Router).
%w[http endpoint solution].each { |area| loader.collapse("#{__dir__}/boto/#{area}") }
loader.setup

module Boto
  # Called from config/app.rb. Yields the configuration of the project being booted and returns it.
  def self.configure
    config = Configuration.capture
    yield config
    config
  end
end
