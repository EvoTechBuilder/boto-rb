# frozen_string_literal: true

Boto.configure do |config|
  config.use BootTestPlugins::Stamp
end
