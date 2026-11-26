# frozen_string_literal: true

module BootTestPlugins
  # Global plugin that marks every response, so the boot test can see it was applied.
  class Stamp < Boto::Plugin
    scope :global

    def call(env, app)
      status, headers, body = app.call(env)
      [status, headers.merge("x-stamp" => "1"), body]
    end
  end
end
